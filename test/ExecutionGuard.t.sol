// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {GuardHarness} from "./Harness.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";
import {RiskAttestationRegistry} from "../contracts/RiskAttestationRegistry.sol";

/**
 * @title ExecutionGuardTest
 * @dev Coverage for the nine checks in `ExecutionGuard.execute()`.
 *
 * The previous version of this file contained one test,
 * `testExecuteRevertsBecauseNotImplementedYet`, which asserted that the guard
 * had deployed to a non-zero address. It never called `execute()`, which is why
 * the agent-id mismatch between the guard and `RegisterAgent.s.sol` was not
 * caught until manual deployment.
 *
 * Adversarial cases live in `attack_scenarios.t.sol`.
 */
contract ExecutionGuardTest is GuardHarness {
    // ------------------------------------------------------------------
    // Happy path
    // ------------------------------------------------------------------

    function test_ApprovedAttestationExecutes() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        vm.prank(agent);
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        assertTrue(target.pinged(), "approved action should have executed");
        assertEq(target.pingCount(), 1, "target should have been called exactly once");
        assertTrue(attestationRegistry.isAttestationUsed(att.intentHash), "attestation should be consumed");
    }

    function test_ApprovedAttestationEmitsExecutionApproved() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        vm.expectEmit(true, true, true, true, address(guard));
        emit ExecutionApproved(att.intentHash, agent, address(target), 0);

        vm.prank(agent);
        guard.execute(address(target), 0, pingCalldata(), att, sig);
    }

    /// @dev Mirrors `ExecutionGuard.ExecutionApproved` for `expectEmit`.
    event ExecutionApproved(bytes32 indexed intentHash, address indexed agent, address indexed target, uint256 value);

    // ------------------------------------------------------------------
    // Decision handling
    // ------------------------------------------------------------------

    function test_DenyReverts() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = deniedAttestation();

        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: execution denied by ARF");
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        assertFalse(target.pinged());
    }

    function test_EscalateReverts() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) =
            attestationFor(RiskAttestationRegistry.Decision.ESCALATE, 570);

        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: ESCALATE requires human approval");
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        assertFalse(target.pinged());
    }

    /// @dev A reverted DENY must leave no trace that could block a later retry.
    function test_DeniedAttestationIsNotConsumed() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = deniedAttestation();

        vm.prank(agent);
        vm.expectRevert();
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        assertFalse(attestationRegistry.isAttestationUsed(att.intentHash));
    }

    // ------------------------------------------------------------------
    // Identity and authorization
    // ------------------------------------------------------------------

    function test_InactiveAgentCannotExecute() public {
        agentRegistry.deactivateAgent(agentId);

        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: agent inactive");
        guard.execute(address(target), 0, pingCalldata(), att, sig);
    }

    function test_UnregisteredAgentCannotExecute() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();
        att.agent = attacker; // never registered

        vm.prank(attacker);
        vm.expectRevert("ExecutionGuard: agent inactive");
        guard.execute(address(target), 0, pingCalldata(), att, sig);
    }

    function test_ThirdPartyCannotSubmitAnotherAgentsAttestation() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        vm.prank(attacker);
        vm.expectRevert("ExecutionGuard: caller not authorized");
        guard.execute(address(target), 0, pingCalldata(), att, sig);
    }

    // ------------------------------------------------------------------
    // Signature and evaluator
    // ------------------------------------------------------------------

    function test_UntrustedEvaluatorIsRejected() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();
        att.evaluator = attacker;

        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: untrusted evaluator");
        guard.execute(address(target), 0, pingCalldata(), att, sig);
    }

    function test_SignatureFromWrongKeyIsRejected() public {
        (RiskAttestationRegistry.RiskAttestation memory att,) = approvedAttestation();

        uint256 wrongPk = 0xB0B;
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", att.intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: invalid signature");
        guard.execute(address(target), 0, pingCalldata(), att, badSig);
    }

    function test_EvaluatorRotationInvalidatesOldSignatures() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        guard.setTrustedEvaluator(attacker);

        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: untrusted evaluator");
        guard.execute(address(target), 0, pingCalldata(), att, sig);
    }

    function test_OnlyOwnerCanRotateEvaluator() public {
        vm.prank(attacker);
        vm.expectRevert();
        guard.setTrustedEvaluator(attacker);
    }

    // ------------------------------------------------------------------
    // Expiry and replay
    // ------------------------------------------------------------------

    function test_ExpiredAttestationIsRejected() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        vm.warp(att.validUntil + 1);

        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: attestation expired");
        guard.execute(address(target), 0, pingCalldata(), att, sig);
    }

    function test_AttestationValidAtExactExpiry() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        // The check is `validUntil >= block.timestamp`, so the boundary is inclusive.
        vm.warp(att.validUntil);

        vm.prank(agent);
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        assertTrue(target.pinged());
    }

    function test_AttestationCannotBeReplayed() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        vm.prank(agent);
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: attestation already used");
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        assertEq(target.pingCount(), 1, "replay must not produce a second call");
    }

    // ------------------------------------------------------------------
    // Intent binding
    // ------------------------------------------------------------------

    function test_AttestationCannotAuthorizeADifferentTarget() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        address otherTarget = address(new CallTargetClone());

        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: intent hash mismatch");
        guard.execute(otherTarget, 0, pingCalldata(), att, sig);
    }

    function test_AttestationCannotAuthorizeDifferentCalldata() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: intent hash mismatch");
        guard.execute(address(target), 0, abi.encodeWithSignature("somethingElse()"), att, sig);
    }

    function test_AttestationCannotAuthorizeADifferentValue() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: intent hash mismatch");
        guard.execute(address(target), 1 wei, pingCalldata(), att, sig);
    }

    // ------------------------------------------------------------------
    // Policy
    // ------------------------------------------------------------------

    function test_InactivePolicyBlocksExecution() public {
        bytes32 policyHash = keccak256("treasury-policy-v1");
        policyRegistry.setPolicy(policyHash, "treasury policy");
        policyRegistry.deactivatePolicy(policyHash);

        uint256 expiry = block.timestamp + VALID_FOR;
        bytes32 intentHash = intentHashFor(agent, address(target), 0, pingCalldata(), policyHash, expiry);

        RiskAttestationRegistry.RiskAttestation memory att = RiskAttestationRegistry.RiskAttestation({
            intentHash: intentHash,
            policyHash: policyHash,
            modelHash: keccak256("arf-model-v1"),
            riskScore: 40,
            reversibility: RiskAttestationRegistry.Reversibility.REVERSIBLE,
            decision: RiskAttestationRegistry.Decision.APPROVE,
            agent: agent,
            evaluator: evaluator,
            issuedAt: block.timestamp,
            validUntil: expiry,
            rationaleHash: keccak256("because")
        });

        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: policy inactive");
        guard.execute(address(target), 0, pingCalldata(), att, signAsEvaluator(intentHash));
    }

    // ------------------------------------------------------------------
    // Exposure limits
    //
    // These document current behavior rather than desired behavior. The guard
    // holds no balance and is not payable, so `value` is 0 in every real call,
    // which makes the `maxTransactionValue` check unreachable for the ERC-20
    // flows the demo describes, and `dailyLimit` is never read at all.
    // See README "Known Limitations" item 3.
    // ------------------------------------------------------------------

    function test_PerTransactionLimitIsUnreachableForZeroValueCalls() public {
        AgentRegistry.Agent memory a = agentRegistry.getAgent(agentId);
        assertEq(a.maxTransactionValue, MAX_TX, "limit is stored");

        // A zero-value call passes the limit check regardless of what the call
        // actually moves, because the guard does not decode `data`.
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        vm.prank(agent);
        guard.execute(address(target), 0, pingCalldata(), att, sig);

        assertTrue(target.pinged());
    }

    function test_DailyLimitIsStoredButNeverEnforced() public view {
        AgentRegistry.Agent memory a = agentRegistry.getAgent(agentId);
        assertEq(a.dailyLimit, DAILY_LIMIT, "dailyLimit is stored on the agent");
        // There is no accessor, accumulator, or check for it anywhere in
        // ExecutionGuard. This assertion exists to make that visible in the
        // suite rather than only in the README.
    }
}

/// @dev A second target address for intent-binding tests.
contract CallTargetClone {
    function ping() external {}
}
