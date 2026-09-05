// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {GuardHarness} from "./Harness.sol";
import {RiskAttestationRegistry} from "../contracts/RiskAttestationRegistry.sol";

/**
 * @title AttackScenarios
 * @dev Adversarial tests against the execution boundary.
 *
 * Each attack appears twice, deliberately:
 *
 *   test_Exploit_*     demonstrates the vulnerability against the code as it
 *                      stands. These PASS today. They are proof the hole is
 *                      real and reachable, not a theoretical reading of the
 *                      source. Delete each one as its fix lands — a passing
 *                      exploit test after the fix means the fix did not work.
 *
 *   test_Regression_*  asserts the behavior the protocol claims. These FAIL
 *                      today. They are the definition of done for the Phase 1b
 *                      fixes, and they stay in the suite permanently.
 *
 * Writing only the regression half would be weaker evidence: a test that fails
 * could be failing because the harness is wrong. The exploit half rules that
 * out by showing the exact attack succeeding end to end.
 *
 * See README "Known Limitations" for the prose description of both flaws.
 */
contract AttackScenarios is GuardHarness {
    /**
     * @dev A genuinely separate attestation carrying `att`'s intent hash but
     *      attributed to `who`.
     *
     * This must build a new struct rather than assign from `att`. Solidity
     * `memory` struct assignment aliases; it does not copy.
     */
    function forgedCopyOf(RiskAttestationRegistry.RiskAttestation memory att, address who)
        internal
        pure
        returns (RiskAttestationRegistry.RiskAttestation memory)
    {
        return RiskAttestationRegistry.RiskAttestation({
            intentHash: att.intentHash, // the only field that has to match
            policyHash: bytes32(0),
            modelHash: bytes32(0),
            riskScore: 0,
            reversibility: RiskAttestationRegistry.Reversibility.REVERSIBLE,
            decision: RiskAttestationRegistry.Decision.APPROVE,
            agent: who,
            evaluator: who,
            issuedAt: 0,
            validUntil: 0,
            rationaleHash: bytes32(0)
        });
    }

    // =====================================================================
    // Attack 1 — the evaluator signature does not cover the decision
    //
    // ExecutionGuard recovers the signature over `attestation.intentHash`
    // alone. `intentHash` binds (agent, target, value, data, policyHash,
    // chainId, expiry, nonce) — it does not bind `decision`. Every other field
    // of the struct is caller-supplied calldata.
    //
    // So a signature the evaluator issued alongside a DENY is equally valid
    // alongside an APPROVE for the same transaction. The agent holds it,
    // because it was handed the attestation.
    // =====================================================================

    function test_Exploit_DenyIsExecutableAsApprove() public {
        // The evaluator refuses the action: risk 0.94, decision DENY.
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = deniedAttestation();

        // Sanity: submitted honestly, this is blocked.
        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: execution denied by ARF");
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        assertFalse(target.pinged(), "denied action must not have executed");

        // The agent changes one field. It does not touch the signature, the
        // intent hash, the target, the calldata, or the evaluator address.
        att.decision = RiskAttestationRegistry.Decision.APPROVE;

        vm.prank(agent);
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        // The action the evaluator denied has now executed.
        assertTrue(target.pinged(), "EXPLOIT: denied action executed after flipping decision");
        assertEq(target.pingCount(), 1);
    }

    function test_Exploit_RiskScoreIsAttackerControlled() public {
        // The same hole applied to the audit trail rather than to execution.
        // riskScore is outside intentHash, so the number recorded on chain is
        // whatever the caller says it is.
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = deniedAttestation();

        att.decision = RiskAttestationRegistry.Decision.APPROVE;
        att.riskScore = 0; // evaluator said 940
        att.reversibility = RiskAttestationRegistry.Reversibility.REVERSIBLE;

        vm.prank(agent);
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        assertTrue(target.pinged(), "EXPLOIT: executed with a fabricated risk score");
    }

    function test_Regression_DenyCannotBeExecutedAsApprove() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = deniedAttestation();

        att.decision = RiskAttestationRegistry.Decision.APPROVE;

        // Once the attestation is signed as EIP-712 typed data over the whole
        // struct, mutating any field invalidates the signature.
        vm.prank(agent);
        vm.expectRevert();
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        assertFalse(target.pinged(), "a denied action must never execute");
    }

    function test_Regression_EscalateCannotBeExecutedAsApprove() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) =
            attestationFor(RiskAttestationRegistry.Decision.ESCALATE, 570); // 0.57

        att.decision = RiskAttestationRegistry.Decision.APPROVE;

        vm.prank(agent);
        vm.expectRevert();
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        assertFalse(target.pinged(), "escalation must not be bypassable by the caller");
    }

    function test_Regression_RiskScoreCannotBeFabricated() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        // Legitimate APPROVE, but the caller rewrites the recorded risk.
        att.riskScore = 0;

        vm.prank(agent);
        vm.expectRevert();
        guard.execute(address(target), 0, pingCalldata(), att, sig);
    }

    // =====================================================================
    // Attack 2 — recordAttestation has no caller restriction
    //
    // RiskAttestationRegistry.recordAttestation is `external` with no check on
    // msg.sender. intentHash is derivable from public state — the registry is
    // public, computeIntentHash is public, and the transaction is visible in
    // the mempool.
    //
    // So a third party can consume an intent hash before the agent uses it,
    // and the guard's replay check then rejects the legitimate execution
    // permanently. Fail-closed becomes a denial-of-service primitive.
    // =====================================================================

    function test_Exploit_ThirdPartyCanPermanentlyBlockAnExecution() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        // The attacker needs no signature and no relationship to the agent.
        // A struct carrying the victim's intent hash is enough; every other
        // field can be junk.
        //
        // Build it field by field. `memory` struct assignment in Solidity is a
        // reference, not a copy, so `junk = att` followed by `junk.agent = ...`
        // would silently rewrite the victim's attestation instead of forging a
        // separate one — and the test would then fail with "agent inactive",
        // looking like the exploit had been prevented.
        RiskAttestationRegistry.RiskAttestation memory junk = forgedCopyOf(att, attacker);

        vm.prank(attacker);
        attestationRegistry.recordAttestation(junk);

        assertTrue(attestationRegistry.isAttestationUsed(att.intentHash), "attacker consumed the intent hash");

        // The agent's valid, signed, unexpired, in-policy approval is now dead.
        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: attestation already used");
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        assertFalse(target.pinged(), "EXPLOIT: legitimate approved action was blocked by a third party");
    }

    function test_Exploit_ThirdPartyCanForgeAuditEvents() public {
        // The same unrestricted entry point writes the on-chain audit trail.
        RiskAttestationRegistry.RiskAttestation memory forged;
        forged.intentHash = keccak256("never-evaluated-by-anyone");
        forged.agent = address(0xDECAF);
        forged.evaluator = attacker;
        forged.riskScore = 1;
        forged.decision = RiskAttestationRegistry.Decision.APPROVE;

        vm.expectEmit(true, true, false, true, address(attestationRegistry));
        emit RiskAttestationRegistry.AttestationIssued(
            forged.intentHash, forged.agent, forged.riskScore, forged.decision
        );

        vm.prank(attacker);
        attestationRegistry.recordAttestation(forged);
    }

    function test_Regression_OnlyGuardCanRecordAttestations() public {
        (RiskAttestationRegistry.RiskAttestation memory att,) = approvedAttestation();

        vm.prank(attacker);
        vm.expectRevert();
        attestationRegistry.recordAttestation(att);

        assertFalse(attestationRegistry.isAttestationUsed(att.intentHash), "outsider must not consume an intent hash");
    }

    function test_Regression_PreRecordingDoesNotBlockLegitimateExecution() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        RiskAttestationRegistry.RiskAttestation memory junk = forgedCopyOf(att, attacker);

        vm.prank(attacker);
        try attestationRegistry.recordAttestation(junk) {} catch {}

        // Whether or not the attacker's call reverted, the agent's approved
        // action must still go through.
        vm.prank(agent);
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        assertTrue(target.pinged(), "a third party must not be able to block a valid execution");
    }
}
