// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {GuardHarness} from "./Harness.sol";
import {RiskAttestationRegistry} from "../contracts/RiskAttestationRegistry.sol";

/**
 * @title AnchoringTest
 * @dev The audit trail for decisions that do not execute.
 *
 * Before `anchorDecision`, the chain recorded approvals and nothing else.
 * `ExecutionGuard` emitted `ExecutionDenied` and then reverted, and a reverted
 * transaction produces no logs — so the event was discarded along with the
 * state change it accompanied. Every denial in the system's history was
 * invisible, which is the opposite of what an on-chain governance record is
 * for.
 *
 * The property that makes anchoring safe is that it does not consume. A denial
 * on the record must not block the approval that follows remediation.
 */
contract AnchoringTest is GuardHarness {
    event DecisionAnchored(
        bytes32 indexed digest,
        bytes32 indexed intentHash,
        address indexed agent,
        RiskAttestationRegistry.Decision decision,
        RiskAttestationRegistry.Reversibility reversibility,
        uint16 riskScore,
        bytes32 rationaleHash
    );

    // ------------------------------------------------------------------
    // A refusal becomes a record
    // ------------------------------------------------------------------

    function test_ADenialIsAnchored() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = deniedAttestation();
        bytes32 digest = guard.hashAttestation(att);

        assertFalse(attestationRegistry.isDecisionAnchored(digest));

        vm.expectEmit(true, true, true, true);
        emit DecisionAnchored(
            digest,
            att.intentHash,
            agent,
            RiskAttestationRegistry.Decision.DENY,
            RiskAttestationRegistry.Reversibility.REVERSIBLE,
            940,
            att.rationaleHash
        );
        attestationRegistry.anchorDecision(att, sig);

        assertTrue(attestationRegistry.isDecisionAnchored(digest));
    }

    function test_AnEscalationIsAnchored() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) =
            attestationFor(RiskAttestationRegistry.Decision.ESCALATE, 570);

        attestationRegistry.anchorDecision(att, sig);
        assertTrue(attestationRegistry.isDecisionAnchored(guard.hashAttestation(att)));
    }

    /// @dev Anyone may publish a genuine decision. The signature is the
    ///      authorisation, so an operator or auditor can put a refusal on the
    ///      record even if the agent that was refused would rather they did not.
    function test_AnyoneMayAnchorAGenuineDecision() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = deniedAttestation();

        vm.prank(attacker);
        attestationRegistry.anchorDecision(att, sig);

        assertTrue(attestationRegistry.isDecisionAnchored(guard.hashAttestation(att)));
    }

    // ------------------------------------------------------------------
    // Anchoring must not consume
    // ------------------------------------------------------------------

    /**
     * @dev The property the whole design turns on.
     *
     * If anchoring wrote to `usedAttestations`, recording a refusal would
     * permanently block the intent — the operator takes the backup the denial
     * asked for, the evaluator approves, and execution fails because the
     * denial already burned the intent hash. Governance would become a
     * one-shot denial-of-service on its own users.
     */
    function test_AnchoringADenialDoesNotBlockALaterApproval() public {
        (RiskAttestationRegistry.RiskAttestation memory denied, bytes memory deniedSig) = deniedAttestation();
        attestationRegistry.anchorDecision(denied, deniedSig);

        assertFalse(attestationRegistry.isAttestationUsed(denied.intentHash), "anchoring consumed the intent");

        (RiskAttestationRegistry.RiskAttestation memory approved, bytes memory approvedSig) = approvedAttestation();
        vm.prank(agent);
        guard.execute(address(target), 0, pingCalldata(), approved, approvedSig);

        assertTrue(target.pinged(), "the approval after remediation did not execute");
    }

    /// @dev And the reverse: anchoring an approval does not brick executing it.
    function test_AnchoringAnApprovalDoesNotBlockItsExecution() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        attestationRegistry.anchorDecision(att, sig);

        vm.prank(agent);
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        assertTrue(target.pinged());
    }

    /// @dev Both verdicts about one intent are separate records. The sequence
    ///      -- refused, then permitted -- is the part worth reading.
    function test_BothDecisionsAboutOneIntentCanBeAnchored() public {
        (RiskAttestationRegistry.RiskAttestation memory denied, bytes memory deniedSig) = deniedAttestation();
        (RiskAttestationRegistry.RiskAttestation memory approved, bytes memory approvedSig) = approvedAttestation();

        assertEq(denied.intentHash, approved.intentHash, "fixture no longer shares an intent");

        attestationRegistry.anchorDecision(denied, deniedSig);
        attestationRegistry.anchorDecision(approved, approvedSig);

        assertTrue(attestationRegistry.isDecisionAnchored(guard.hashAttestation(denied)));
        assertTrue(attestationRegistry.isDecisionAnchored(guard.hashAttestation(approved)));
    }

    // ------------------------------------------------------------------
    // The record cannot be forged
    // ------------------------------------------------------------------

    function test_AnUnsignedDecisionIsRefused() public {
        (RiskAttestationRegistry.RiskAttestation memory att,) = deniedAttestation();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xB0B, guard.hashAttestation(att));

        vm.expectRevert("RiskAttestationRegistry: invalid signature");
        attestationRegistry.anchorDecision(att, abi.encodePacked(r, s, v));
    }

    /// @dev The forgery the original vulnerability allowed, in the audit trail:
    ///      taking a signed refusal and recording it as an approval.
    function test_ATamperedDecisionIsRefused() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = deniedAttestation();

        // Built field by field, not assigned: `memory` struct assignment
        // aliases, so mutating a "copy" would rewrite the original.
        RiskAttestationRegistry.RiskAttestation memory forged = RiskAttestationRegistry.RiskAttestation({
            intentHash: att.intentHash,
            policyHash: att.policyHash,
            modelHash: att.modelHash,
            riskScore: att.riskScore,
            reversibility: att.reversibility,
            decision: RiskAttestationRegistry.Decision.APPROVE,
            agent: att.agent,
            evaluator: att.evaluator,
            issuedAt: att.issuedAt,
            validUntil: att.validUntil,
            rationaleHash: att.rationaleHash
        });

        vm.expectRevert("RiskAttestationRegistry: invalid signature");
        attestationRegistry.anchorDecision(forged, sig);
    }

    function test_AnAttestationNamingAnotherEvaluatorIsRefused() public {
        (RiskAttestationRegistry.RiskAttestation memory att,) = deniedAttestation();

        RiskAttestationRegistry.RiskAttestation memory forged = RiskAttestationRegistry.RiskAttestation({
            intentHash: att.intentHash,
            policyHash: att.policyHash,
            modelHash: att.modelHash,
            riskScore: att.riskScore,
            reversibility: att.reversibility,
            decision: att.decision,
            agent: att.agent,
            evaluator: attacker,
            issuedAt: att.issuedAt,
            validUntil: att.validUntil,
            rationaleHash: att.rationaleHash
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xB0B, guard.hashAttestation(forged));

        vm.expectRevert("RiskAttestationRegistry: untrusted evaluator");
        attestationRegistry.anchorDecision(forged, abi.encodePacked(r, s, v));
    }

    function test_TheSameDecisionCannotBeAnchoredTwice() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = deniedAttestation();

        attestationRegistry.anchorDecision(att, sig);

        vm.expectRevert("RiskAttestationRegistry: already anchored");
        attestationRegistry.anchorDecision(att, sig);
    }

    // ------------------------------------------------------------------
    // Undetermined reversibility
    // ------------------------------------------------------------------

    /**
     * @dev `undetermined` is what the actuator reports when it cannot read
     *      enough provider state to classify an action. The execution gate
     *      treats it as harshly as IRREVERSIBLE, but the record must not say
     *      IRREVERSIBLE — that would assert the system determined permanence
     *      when it determined nothing.
     */
    function test_UndeterminedReversibilityIsRecordedAsItself() public {
        uint256 expiry = block.timestamp + VALID_FOR;
        RiskAttestationRegistry.RiskAttestation memory att = RiskAttestationRegistry.RiskAttestation({
            intentHash: intentHashFor(agent, address(target), 0, pingCalldata(), bytes32(0), expiry),
            policyHash: bytes32(0),
            modelHash: keccak256("arf-model-v1"),
            riskScore: 800,
            reversibility: RiskAttestationRegistry.Reversibility.UNDETERMINED,
            decision: RiskAttestationRegistry.Decision.DENY,
            agent: agent,
            evaluator: evaluator,
            issuedAt: block.timestamp,
            validUntil: expiry,
            rationaleHash: keccak256("could not read SnapLock retention")
        });

        vm.expectEmit(true, true, true, true);
        emit DecisionAnchored(
            guard.hashAttestation(att),
            att.intentHash,
            agent,
            RiskAttestationRegistry.Decision.DENY,
            RiskAttestationRegistry.Reversibility.UNDETERMINED,
            800,
            att.rationaleHash
        );
        attestationRegistry.anchorDecision(att, signAsEvaluator(att));
    }

    /**
     * @dev An approval of an action nobody could classify is self-contradictory.
     *
     * Off-chain this pair cannot arise: `Compensation.gating_reversibility`
     * collapses an unreadable classification to IRREVERSIBLE before the
     * decision is made, so the evaluator refuses. The guard enforces it anyway
     * — if this attestation ever appears, the evaluator is compromised or
     * broken, and the guard is the boundary rather than a reflection of the
     * engine's good behaviour.
     */
    function test_AnUnclassifiedActionCannotBeApproved() public {
        uint256 expiry = block.timestamp + VALID_FOR;
        RiskAttestationRegistry.RiskAttestation memory att = RiskAttestationRegistry.RiskAttestation({
            intentHash: intentHashFor(agent, address(target), 0, pingCalldata(), bytes32(0), expiry),
            policyHash: bytes32(0),
            modelHash: keccak256("arf-model-v1"),
            riskScore: 100,
            reversibility: RiskAttestationRegistry.Reversibility.UNDETERMINED,
            decision: RiskAttestationRegistry.Decision.APPROVE,
            agent: agent,
            evaluator: evaluator,
            issuedAt: block.timestamp,
            validUntil: expiry,
            rationaleHash: keccak256("provider read failed")
        });

        // Signed before arming expectRevert: signAsEvaluator calls
        // guard.hashAttestation, a view call. Signing inline as a call
        // argument evaluates that call first and expectRevert intercepts it
        // instead of execute() -- exactly the failure mode this fixes.
        bytes memory sig = signAsEvaluator(att);

        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: cannot approve an unclassified action");
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        assertFalse(target.pinged());
    }

    /// @dev But it can still be anchored: the record is of what was decided,
    ///      including a decision the guard then refused to act on.
    function test_AnUnclassifiedApprovalIsStillRecordable() public {
        uint256 expiry = block.timestamp + VALID_FOR;
        RiskAttestationRegistry.RiskAttestation memory att = RiskAttestationRegistry.RiskAttestation({
            intentHash: intentHashFor(agent, address(target), 0, pingCalldata(), bytes32(0), expiry),
            policyHash: bytes32(0),
            modelHash: keccak256("arf-model-v1"),
            riskScore: 100,
            reversibility: RiskAttestationRegistry.Reversibility.UNDETERMINED,
            decision: RiskAttestationRegistry.Decision.APPROVE,
            agent: agent,
            evaluator: evaluator,
            issuedAt: block.timestamp,
            validUntil: expiry,
            rationaleHash: keccak256("provider read failed")
        });

        attestationRegistry.anchorDecision(att, signAsEvaluator(att));
        assertTrue(attestationRegistry.isDecisionAnchored(guard.hashAttestation(att)));
    }
}
