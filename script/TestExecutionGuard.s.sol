// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ExecutionGuard} from "../contracts/ExecutionGuard.sol";
import {RiskAttestationRegistry} from "../contracts/RiskAttestationRegistry.sol";

contract TestExecutionGuard is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // === NEW DEPLOYMENT ADDRESS ===
        address guardAddr = 0x43D164C79718614fe583b5fADF29875F8938740c;

        ExecutionGuard guard = ExecutionGuard(guardAddr);

        // Ensure trusted evaluator is deployer
        address currentTrusted = guard.trustedEvaluator();
        console.log("Current trusted evaluator:", currentTrusted);

        if (currentTrusted != deployer) {
            vm.startBroadcast(deployerPrivateKey);
            guard.setTrustedEvaluator(deployer);
            vm.stopBroadcast();
            console.log("Trusted evaluator updated to deployer");
        }

        // Prepare transaction
        address agent = deployer;
        address target = deployer;
        uint256 value = 0.001 ether;
        bytes memory data = "";
        bytes32 policyHash = bytes32(0);
        uint256 chainId = 10143;
        uint256 expiry = block.timestamp + 3600;
        uint256 nonce = 1;

        bytes32 intentHash = guard.computeIntentHash(
            agent,
            target,
            value,
            data,
            policyHash,
            chainId,
            expiry,
            nonce
        );
        console.log("Intent Hash:", vm.toString(intentHash));

        // Build attestation using named struct fields to avoid stack issues
        RiskAttestationRegistry.RiskAttestation memory attestation;
        attestation.intentHash = intentHash;
        attestation.policyHash = policyHash;
        attestation.modelHash = bytes32(0);
        attestation.riskScore = 50;
        attestation.reversibility = RiskAttestationRegistry.Reversibility.REVERSIBLE;
        attestation.decision = RiskAttestationRegistry.Decision.APPROVE;
        attestation.agent = agent;
        attestation.evaluator = deployer;
        attestation.issuedAt = block.timestamp;
        attestation.validUntil = expiry;
        attestation.rationaleHash = bytes32(0);

        // Sign the intent hash
        bytes32 signedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", intentHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        console.log("Signature generated");

        // Execute – ExecutionGuard will record the attestation internally
        vm.startBroadcast(deployerPrivateKey);
        guard.execute(
            target,
            value,
            data,
            attestation,
            signature
        );
        vm.stopBroadcast();

        console.log("ExecutionGuard.execute() called successfully");
    }
}
