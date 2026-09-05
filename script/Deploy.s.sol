// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";
import {PolicyRegistry} from "../contracts/PolicyRegistry.sol";
import {RiskAttestationRegistry} from "../contracts/RiskAttestationRegistry.sol";
import {ExecutionGuard} from "../contracts/ExecutionGuard.sol";
import {TreasuryVault} from "../contracts/TreasuryVault.sol";
import {AuditRegistry} from "../contracts/AuditRegistry.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        AgentRegistry agentRegistry = new AgentRegistry();
        console.log("AgentRegistry deployed at:", address(agentRegistry));

        PolicyRegistry policyRegistry = new PolicyRegistry();
        console.log("PolicyRegistry deployed at:", address(policyRegistry));

        RiskAttestationRegistry attestationRegistry = new RiskAttestationRegistry();
        console.log("RiskAttestationRegistry deployed at:", address(attestationRegistry));

        // Pass deployer as trusted evaluator (for testing)
        ExecutionGuard executionGuard = new ExecutionGuard(
            address(agentRegistry), address(policyRegistry), address(attestationRegistry), msg.sender
        );
        console.log("ExecutionGuard deployed at:", address(executionGuard));

        // Required. The registry rejects every consume until it knows its
        // guard, so execution fails closed if this is ever skipped.
        attestationRegistry.setExecutionGuard(address(executionGuard));
        console.log("RiskAttestationRegistry bound to guard");

        TreasuryVault treasuryVault = new TreasuryVault();
        console.log("TreasuryVault deployed at:", address(treasuryVault));

        AuditRegistry auditRegistry = new AuditRegistry();
        console.log("AuditRegistry deployed at:", address(auditRegistry));

        vm.stopBroadcast();
    }
}
