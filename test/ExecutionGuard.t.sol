// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {GuardHarness} from "./Harness.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";
import {ExecutionGuard} from "../contracts/ExecutionGuard.sol";
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
    // EIP-712 binding
    // ------------------------------------------------------------------

    /// @dev Every field must be covered, not just the ones an attacker is
    ///      likeliest to reach for. This walks the whole struct.
    function test_MutatingAnyAttestationFieldInvalidatesTheSignature() public {
        (RiskAttestationRegistry.RiskAttestation memory base, bytes memory sig) = approvedAttestation();

        for (uint256 i = 0; i < 8; i++) {
            RiskAttestationRegistry.RiskAttestation memory att = approvedCopy();

            if (i == 0) att.policyHash = keccak256("other-policy");
            else if (i == 1) att.modelHash = keccak256("other-model");
            else if (i == 2) att.riskScore = 999;
            else if (i == 3) att.reversibility = RiskAttestationRegistry.Reversibility.IRREVERSIBLE;
            else if (i == 4) att.decision = RiskAttestationRegistry.Decision.DENY;
            else if (i == 5) att.issuedAt = base.issuedAt - 1;
            else if (i == 6) att.validUntil = base.validUntil + 1;
            else if (i == 7) att.rationaleHash = keccak256("different reason");

            assertTrue(
                guard.hashAttestation(att) != guard.hashAttestation(base), "field must change the EIP-712 digest"
            );

            vm.prank(agent);
            vm.expectRevert();
            guard.execute(address(target), 0, pingCalldata(), att, sig);
        }

        assertFalse(target.pinged(), "no mutated attestation may execute");
    }

    function test_DomainSeparatorBindsChainAndContract() public view {
        bytes32 expected = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("ARF Onchain"),
                keccak256("1"),
                block.chainid,
                address(guard)
            )
        );
        assertEq(guard.domainSeparator(), expected, "domain must bind this chain and this guard");
    }

    /// @dev A signature valid for one guard must not work on another. This is
    ///      what stops an attestation being replayed against a redeployment.
    function test_SignatureDoesNotTransferToAnotherGuardDeployment() public {
        (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig) = approvedAttestation();

        ExecutionGuard otherGuard = new ExecutionGuard(
            address(agentRegistry), address(policyRegistry), address(attestationRegistry), evaluator
        );
        attestationRegistry.setExecutionGuard(address(otherGuard));

        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: invalid signature");
        otherGuard.execute(address(target), 0, pingCalldata(), att, sig);
    }

    // ------------------------------------------------------------------
    // Registry binding
    // ------------------------------------------------------------------

    function test_ExecutionFailsClosedIfRegistryHasNoGuard() public {
        RiskAttestationRegistry fresh = new RiskAttestationRegistry();
        ExecutionGuard unbound =
            new ExecutionGuard(address(agentRegistry), address(policyRegistry), address(fresh), evaluator);

        uint256 expiry = block.timestamp + VALID_FOR;
        bytes32 intentHash = unbound.computeIntentHash(
            agent, address(target), 0, pingCalldata(), bytes32(0), block.chainid, block.timestamp + VALID_FOR, 0
        );

        // Deliberately not calling fresh.setExecutionGuard.
        RiskAttestationRegistry.RiskAttestation memory att = approvedCopy();
        att.intentHash = intentHash;
        att.validUntil = expiry;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(EVALUATOR_PK, unbound.hashAttestation(att));

        vm.prank(agent);
        vm.expectRevert("RiskAttestationRegistry: not the guard");
        unbound.execute(address(target), 0, pingCalldata(), att, abi.encodePacked(r, s, v));
    }

    function test_OnlyOwnerCanBindTheGuard() public {
        vm.prank(attacker);
        vm.expectRevert();
        attestationRegistry.setExecutionGuard(attacker);
    }

    function test_GuardCannotBeBoundToZero() public {
        vm.expectRevert("RiskAttestationRegistry: zero guard");
        attestationRegistry.setExecutionGuard(address(0));
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

        // Sign before arming expectRevert. `signAsEvaluator` calls
        // `guard.hashAttestation`, and an external call in argument position
        // would consume the expectation and satisfy it by succeeding.
        bytes memory sig = signAsEvaluator(att);

        vm.prank(agent);
        vm.expectRevert("ExecutionGuard: policy inactive");
        guard.execute(address(target), 0, pingCalldata(), att, sig);
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
