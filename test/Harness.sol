// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";
import {PolicyRegistry} from "../contracts/PolicyRegistry.sol";
import {RiskAttestationRegistry} from "../contracts/RiskAttestationRegistry.sol";
import {ExecutionGuard} from "../contracts/ExecutionGuard.sol";

/**
 * @title CallTarget
 * @dev Minimal call target. `ping()` flips a flag so a test can tell whether an
 *      execution actually reached the target, rather than inferring it from the
 *      absence of a revert.
 */
contract CallTarget {
    bool public pinged;
    uint256 public pingCount;

    function ping() external {
        pinged = true;
        pingCount++;
    }
}

/**
 * @title GuardHarness
 * @dev Shared setup for the ExecutionGuard tests.
 *
 * The pieces every test needs are the same: a deployed stack, a registered
 * agent whose id is in the form the guard actually derives, an evaluator whose
 * private key the test controls, and a helper that signs an attestation the way
 * `ExecutionGuard.execute()` expects.
 *
 * Note the agent id. `ExecutionGuard` computes it as
 * `keccak256(abi.encodePacked(attestation.agent))` and does not accept one from
 * the caller, so an agent registered under any other id is unreachable. The
 * previously shipped `RegisterAgent.s.sol` and the previous version of this
 * test both used `keccak256("some-name")`, which is why neither ever exercised
 * `execute()`.
 */
abstract contract GuardHarness is Test {
    AgentRegistry internal agentRegistry;
    PolicyRegistry internal policyRegistry;
    RiskAttestationRegistry internal attestationRegistry;
    ExecutionGuard internal guard;
    CallTarget internal target;

    uint256 internal constant EVALUATOR_PK = 0xA11CE;
    address internal evaluator;

    address internal agent = address(0xA6E17);
    bytes32 internal agentId;

    address internal attacker = address(0xBAD);

    uint256 internal constant MAX_TX = 10_000 ether;
    uint256 internal constant DAILY_LIMIT = 50_000 ether;

    /// @dev How far in the future attestations are valid by default.
    uint256 internal constant VALID_FOR = 1 hours;

    /**
     * @dev The "explicitly unpoliced" sentinel policy hash.
     *
     * `ExecutionGuard.execute()` used to skip its policy check entirely
     * when `attestation.policyHash == bytes32(0)`. It no longer does --
     * every attestation must reference a registered, active policy, and
     * "no policy applies" is now a real, auditable choice: register this
     * hash and reference it deliberately, rather than relying on an
     * ambient zero value nobody had to opt into.
     *
     * Pinned to `keccak256(arf_enterprise.onchain.policy_spec.canonical_
     * bytes(UNPOLICED_SPEC))` -- see `test_onchain_policy_spec.py`'s
     * `PINNED_UNPOLICED_HASH`. If either side's encoding ever changes, both
     * must change together or a real evaluator's "unpoliced" attestation
     * gets rejected here with "policy inactive" for a reason nothing in
     * this file explains.
     */
    bytes32 internal constant UNPOLICED_POLICY_HASH =
        0x5e368ac55dc3cbcaf7b27c1723e72a658ff6afdf7ec05f32b433ed309c77fb8c;

    function setUp() public virtual {
        evaluator = vm.addr(EVALUATOR_PK);

        agentRegistry = new AgentRegistry();
        policyRegistry = new PolicyRegistry();
        attestationRegistry = new RiskAttestationRegistry();
        guard = new ExecutionGuard(
            address(agentRegistry), address(policyRegistry), address(attestationRegistry), evaluator
        );
        // Without this the registry rejects every consume and nothing executes.
        attestationRegistry.setExecutionGuard(address(guard));
        target = new CallTarget();

        agentId = agentRegistry.registerAgent(agent, agent, MAX_TX, DAILY_LIMIT);
        assertEq(agentId, agentRegistry.agentIdFor(agent), "registry derived an id the guard will not look up");

        // Registered so attestationFor()'s default (unpoliced) attestations
        // pass the guard's policy check -- see UNPOLICED_POLICY_HASH.
        policyRegistry.setPolicy(UNPOLICED_POLICY_HASH, "explicitly unpoliced -- no policy applies");

        // Timestamps start at 1 in Foundry; move forward so expiry arithmetic
        // below cannot underflow.
        vm.warp(1_000_000);
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /// @dev Calldata used by every test that needs a real, observable call.
    function pingCalldata() internal pure returns (bytes memory) {
        return abi.encodeWithSignature("ping()");
    }

    /// @dev The intent hash the guard will recompute for this transaction.
    function intentHashFor(
        address who,
        address to,
        uint256 value,
        bytes memory data,
        bytes32 policyHash,
        uint256 expiry
    ) internal view returns (bytes32) {
        AgentRegistry.Agent memory a = agentRegistry.getAgent(keccak256(abi.encodePacked(who)));
        return guard.computeIntentHash(who, to, value, data, policyHash, block.chainid, expiry, a.nonce);
    }

    /**
     * @dev Sign an attestation as the trusted evaluator.
     *
     * The guard verifies an EIP-712 digest over the whole struct, so this takes
     * the attestation rather than just its intent hash. Signing only the intent
     * hash — what the guard used to check — is what allowed a signed DENY to be
     * executed as an APPROVE.
     */
    function signAsEvaluator(RiskAttestationRegistry.RiskAttestation memory att) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(EVALUATOR_PK, guard.hashAttestation(att));
        return abi.encodePacked(r, s, v);
    }

    /**
     * @dev Build a well-formed attestation for a `ping()` call to `target`.
     *
     * `decision` and `riskScore` are parameters rather than fixed, because the
     * whole question these tests exist to answer is what happens when those two
     * fields disagree with what the evaluator actually signed.
     */
    function attestationFor(RiskAttestationRegistry.Decision decision, uint16 riskScore)
        internal
        view
        returns (RiskAttestationRegistry.RiskAttestation memory att, bytes memory sig)
    {
        uint256 expiry = block.timestamp + VALID_FOR;
        bytes32 intentHash = intentHashFor(agent, address(target), 0, pingCalldata(), UNPOLICED_POLICY_HASH, expiry);

        att = RiskAttestationRegistry.RiskAttestation({
            intentHash: intentHash,
            policyHash: UNPOLICED_POLICY_HASH,
            modelHash: keccak256("arf-model-v1"),
            riskScore: riskScore,
            reversibility: RiskAttestationRegistry.Reversibility.REVERSIBLE,
            decision: decision,
            agent: agent,
            evaluator: evaluator,
            issuedAt: block.timestamp,
            validUntil: expiry,
            rationaleHash: keccak256("because")
        });

        sig = signAsEvaluator(att);
    }

    /// @dev An attestation the evaluator would actually issue for a safe action.
    function approvedAttestation()
        internal
        view
        returns (RiskAttestationRegistry.RiskAttestation memory, bytes memory)
    {
        return attestationFor(RiskAttestationRegistry.Decision.APPROVE, 40); // 0.04
    }

    /**
     * @dev A fresh, independent approved attestation.
     *
     * Use this instead of assigning from another attestation: Solidity `memory`
     * struct assignment aliases rather than copies, so `copy = original`
     * followed by `copy.field = x` silently rewrites the original.
     */
    function approvedCopy() internal view returns (RiskAttestationRegistry.RiskAttestation memory att) {
        (att,) = attestationFor(RiskAttestationRegistry.Decision.APPROVE, 40);
    }

    /// @dev An attestation the evaluator would issue for an action it refuses.
    function deniedAttestation() internal view returns (RiskAttestationRegistry.RiskAttestation memory, bytes memory) {
        return attestationFor(RiskAttestationRegistry.Decision.DENY, 940); // 0.94
    }
}
