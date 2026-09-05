// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ExecutionGuard} from "../contracts/ExecutionGuard.sol";
import {RiskAttestationRegistry} from "../contracts/RiskAttestationRegistry.sol";

contract TestExecutionGuard is Script {
    /// @dev Split out of `run()` so the whole flow does not sit in one stack
    ///      frame — as written it exceeded the EVM's 16-slot reach and the
    ///      repository would not compile at all ("Stack too deep").
    function buildAttestation(bytes32 intentHash, bytes32 policyHash, address agent, address evaluator, uint256 expiry)
        internal
        view
        returns (RiskAttestationRegistry.RiskAttestation memory attestation)
    {
        attestation.intentHash = intentHash;
        attestation.policyHash = policyHash;
        attestation.modelHash = bytes32(0);
        attestation.riskScore = 50;
        attestation.reversibility = RiskAttestationRegistry.Reversibility.REVERSIBLE;
        attestation.decision = RiskAttestationRegistry.Decision.APPROVE;
        attestation.agent = agent;
        attestation.evaluator = evaluator;
        attestation.issuedAt = block.timestamp;
        attestation.validUntil = expiry;
        attestation.rationaleHash = bytes32(0);
    }

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // NOTE: this address matches neither the deployment recorded in
        // docs/deployments.md (0x58B7fa76...) nor any other documented guard.
        // Confirm it before running this script against a live network.
        ExecutionGuard guard = ExecutionGuard(0x43D164C79718614fe583b5fADF29875F8938740c);

        ensureEvaluator(guard, pk);
        executeSample(guard, pk);
    }

    /// @dev Point the guard at the deployer as trusted evaluator, if it is not already.
    function ensureEvaluator(ExecutionGuard guard, uint256 pk) internal {
        address deployer = vm.addr(pk);
        address currentTrusted = guard.trustedEvaluator();
        console.log("Current trusted evaluator:", currentTrusted);

        if (currentTrusted != deployer) {
            vm.startBroadcast(pk);
            guard.setTrustedEvaluator(deployer);
            vm.stopBroadcast();
            console.log("Trusted evaluator updated to deployer");
        }
    }

    /// @dev Build, sign and submit one zero-value self-call through the guard.
    function executeSample(ExecutionGuard guard, uint256 pk) internal {
        address deployer = vm.addr(pk);
        uint256 expiry = block.timestamp + 3600;

        bytes32 intentHash = guard.computeIntentHash(
            deployer, deployer, 0, "", bytes32(0), block.chainid, expiry, 0
        );
        console.log("Intent Hash:", vm.toString(intentHash));

        RiskAttestationRegistry.RiskAttestation memory attestation =
            buildAttestation(intentHash, bytes32(0), deployer, deployer, expiry);

        vm.startBroadcast(pk);
        guard.execute(deployer, 0, "", attestation, signAttestation(guard, pk, attestation));
        vm.stopBroadcast();

        console.log("ExecutionGuard.execute() called successfully");
    }

    /// @dev Sign an attestation as EIP-712 typed data, the way ExecutionGuard verifies it.
    function signAttestation(ExecutionGuard guard, uint256 pk, RiskAttestationRegistry.RiskAttestation memory a)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, guard.hashAttestation(a));
        return abi.encodePacked(r, s, v);
    }
}
