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

        ExecutionGuard executionGuard = new ExecutionGuard(
            address(agentRegistry),
            address(policyRegistry),
            address(attestationRegistry)
        );
        console.log("ExecutionGuard deployed at:", address(executionGuard));

        TreasuryVault treasuryVault = new TreasuryVault();
        console.log("TreasuryVault deployed at:", address(treasuryVault));

        AuditRegistry auditRegistry = new AuditRegistry();
        console.log("AuditRegistry deployed at:", address(auditRegistry));

        vm.stopBroadcast();
    }
}
