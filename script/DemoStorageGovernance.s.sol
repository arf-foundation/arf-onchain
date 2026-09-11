// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";
import {PolicyRegistry} from "../contracts/PolicyRegistry.sol";
import {RiskAttestationRegistry} from "../contracts/RiskAttestationRegistry.sol";
import {ExecutionGuard} from "../contracts/ExecutionGuard.sol";

/**
 * @title DemoStorageGovernance
 * @dev Runnable proof of the README's "Why This Needs A Chain, Not Just A
 *      Log" argument.
 *
 * One verb -- `delete_volume` -- requested three times against the same
 * storage volume. Each request gets a different reading of live provider
 * state (final backup taken, final backup skipped, provider unreadable),
 * so each gets a different reversibility classification, decision and
 * signed attestation. All three -- including the two refusals -- are
 * anchored on-chain via `RiskAttestationRegistry.anchorDecision`, which
 * succeeds precisely because it executes nothing. That is the property a
 * database audit table cannot offer: a denied action never runs, so an
 * ordinary execution log has nothing to show for it, and a log row can
 * always be edited or deleted by whoever holds the credentials. An
 * anchored attestation cannot.
 *
 * Deploys a fresh local stack rather than pointing at a live testnet
 * deployment, so this is self-contained:
 *
 *   forge script script/DemoStorageGovernance.s.sol -vvv
 *
 * runs it with no `.env`, no RPC, and no funded wallet. `EVALUATOR_PK`
 * below is a well-known demo key, not a real evaluator identity -- a real
 * evaluator key is loaded from a secrets manager and never appears in a
 * file. The classification inputs (which case gets which reversibility and
 * risk score) are illustrative stand-ins for a real provider read: the
 * production reversibility engine that performs this classification
 * against a live cloud API is proprietary and lives outside this
 * repository. See "Public vs. Proprietary Components" in the README.
 */
contract DemoStorageGovernance is Script {
    uint256 internal constant EVALUATOR_PK = 0x1111111111111111111111111111111111111111111111111111111111111;
    address internal constant AGENT = address(0xA9E47);
    address internal constant TARGET = address(0x50A6E);

    function run() external {
        address evaluator = vm.addr(EVALUATOR_PK);

        vm.startBroadcast(EVALUATOR_PK);
        AgentRegistry agentRegistry = new AgentRegistry();
        PolicyRegistry policyRegistry = new PolicyRegistry();
        RiskAttestationRegistry attestationRegistry = new RiskAttestationRegistry();
        ExecutionGuard guard = new ExecutionGuard(
            address(agentRegistry), address(policyRegistry), address(attestationRegistry), evaluator
        );
        attestationRegistry.setExecutionGuard(address(guard));
        vm.stopBroadcast();

        console.log("=== One verb, three readings of live state ===");
        console.log("volume : fs-0123456789abcdef0/fsvol-0123456789abcdef0");
        console.log("action : delete_volume (the same action in all three cases)");
        console.log("");

        anchorCase(
            attestationRegistry,
            guard,
            "1. final backup taken -- restore possible, but under a new volume id",
            RiskAttestationRegistry.Reversibility.COMPENSABLE,
            RiskAttestationRegistry.Decision.ESCALATE,
            420,
            0
        );

        anchorCase(
            attestationRegistry,
            guard,
            "2. SkipFinalBackup=true -- nothing to restore from",
            RiskAttestationRegistry.Reversibility.IRREVERSIBLE,
            RiskAttestationRegistry.Decision.DENY,
            940,
            1
        );

        anchorCase(
            attestationRegistry,
            guard,
            "3. provider unreadable -- recoverability cannot be determined",
            RiskAttestationRegistry.Reversibility.UNDETERMINED,
            RiskAttestationRegistry.Decision.DENY,
            800,
            2
        );

        console.log("");
        console.log("All three verdicts, including both refusals, are now permanently");
        console.log("recorded in RiskAttestationRegistry.isDecisionAnchored -- in");
        console.log("transactions that succeeded by executing nothing.");
    }

    /// @dev Split out of `run()` to keep each stack frame small -- see
    ///      TestExecutionGuard.s.sol's note on "stack too deep".
    function anchorCase(
        RiskAttestationRegistry attestationRegistry,
        ExecutionGuard guard,
        string memory label,
        RiskAttestationRegistry.Reversibility reversibility,
        RiskAttestationRegistry.Decision decision,
        uint16 riskScoreBasisPoints,
        uint256 nonce
    ) internal {
        RiskAttestationRegistry.RiskAttestation memory attestation =
            buildAttestation(guard, reversibility, decision, riskScoreBasisPoints, nonce);
        bytes32 digest = guard.hashAttestation(attestation);
        bytes memory signature = sign(guard, attestation);

        vm.startBroadcast(EVALUATOR_PK);
        attestationRegistry.anchorDecision(attestation, signature);
        vm.stopBroadcast();

        console.log(label);
        console.log("  reversibility :", reversibilityName(reversibility));
        console.log("  decision      :", decisionName(decision));
        console.log("  digest        :", vm.toString(digest));
        console.log("  anchored      :", attestationRegistry.isDecisionAnchored(digest));
    }

    /// @dev `console.log(string, uint256)` silently no-ops against this
    ///      forge-std/forge pairing (a selector mismatch, confirmed with a
    ///      minimal repro) -- routing every value through a string avoids it,
    ///      and names read better than raw enum ints besides.
    function reversibilityName(RiskAttestationRegistry.Reversibility reversibility)
        internal
        pure
        returns (string memory)
    {
        if (reversibility == RiskAttestationRegistry.Reversibility.REVERSIBLE) return "REVERSIBLE (0)";
        if (reversibility == RiskAttestationRegistry.Reversibility.COMPENSABLE) return "COMPENSABLE (1)";
        if (reversibility == RiskAttestationRegistry.Reversibility.IRREVERSIBLE) return "IRREVERSIBLE (2)";
        return "UNDETERMINED (3)";
    }

    function decisionName(RiskAttestationRegistry.Decision decision) internal pure returns (string memory) {
        if (decision == RiskAttestationRegistry.Decision.APPROVE) return "APPROVE (0)";
        if (decision == RiskAttestationRegistry.Decision.ESCALATE) return "ESCALATE (1)";
        return "DENY (2)";
    }

    function buildAttestation(
        ExecutionGuard guard,
        RiskAttestationRegistry.Reversibility reversibility,
        RiskAttestationRegistry.Decision decision,
        uint16 riskScoreBasisPoints,
        uint256 nonce
    ) internal view returns (RiskAttestationRegistry.RiskAttestation memory attestation) {
        uint256 expiry = block.timestamp + 3600;
        bytes32 intentHash = guard.computeIntentHash(AGENT, TARGET, 0, "", bytes32(0), block.chainid, expiry, nonce);

        attestation.intentHash = intentHash;
        attestation.policyHash = bytes32(0);
        attestation.modelHash = bytes32(uint256(0x33));
        attestation.riskScore = riskScoreBasisPoints;
        attestation.reversibility = reversibility;
        attestation.decision = decision;
        attestation.agent = AGENT;
        attestation.evaluator = vm.addr(EVALUATOR_PK);
        attestation.issuedAt = block.timestamp;
        attestation.validUntil = expiry;
        attestation.rationaleHash = bytes32(uint256(0x44));
    }

    /// @dev Sign an attestation as EIP-712 typed data, the way
    ///      `RiskAttestationRegistry.anchorDecision` verifies it.
    function sign(ExecutionGuard guard, RiskAttestationRegistry.RiskAttestation memory attestation)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(EVALUATOR_PK, guard.hashAttestation(attestation));
        return abi.encodePacked(r, s, v);
    }
}
