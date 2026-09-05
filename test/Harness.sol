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

    function setUp() public virtual {
        evaluator = vm.addr(EVALUATOR_PK);

        agentRegistry = new AgentRegistry();
        policyRegistry = new PolicyRegistry();
        attestationRegistry = new RiskAttestationRegistry();
        guard = new ExecutionGuard(
            address(agentRegistry), address(policyRegistry), address(attestationRegistry), evaluator
        );
        target = new CallTarget();

        agentId = keccak256(abi.encodePacked(agent));
        agentRegistry.registerAgent(agentId, agent, agent, MAX_TX, DAILY_LIMIT);

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
    function intentHashFor(address who, address to, uint256 value, bytes memory data, bytes32 policyHash, uint256 expiry)
        internal
        view
        returns (bytes32)
    {
        AgentRegistry.Agent memory a = agentRegistry.getAgent(keccak256(abi.encodePacked(who)));
        return guard.computeIntentHash(who, to, value, data, policyHash, block.chainid, expiry, a.nonce);
    }

    /// @dev Sign a digest as the trusted evaluator, in the format the guard checks.
    function signAsEvaluator(bytes32 intentHash) internal pure returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(EVALUATOR_PK, digest);
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
        bytes32 intentHash = intentHashFor(agent, address(target), 0, pingCalldata(), bytes32(0), expiry);

        att = RiskAttestationRegistry.RiskAttestation({
            intentHash: intentHash,
            policyHash: bytes32(0),
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

        sig = signAsEvaluator(intentHash);
    }

    /// @dev An attestation the evaluator would actually issue for a safe action.
    function approvedAttestation()
        internal
        view
        returns (RiskAttestationRegistry.RiskAttestation memory, bytes memory)
    {
        return attestationFor(RiskAttestationRegistry.Decision.APPROVE, 40); // 0.04
    }

    /// @dev An attestation the evaluator would issue for an action it refuses.
    function deniedAttestation() internal view returns (RiskAttestationRegistry.RiskAttestation memory, bytes memory) {
        return attestationFor(RiskAttestationRegistry.Decision.DENY, 940); // 0.94
    }
}
