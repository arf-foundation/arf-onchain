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
    /**
     * @dev `msg.sender` inside a Forge script's `run()` is Foundry's script
     * default caller (`keccak256("foundry default caller")`, a hash-derived
     * constant no one holds a private key for), not the address broadcasting
     * the transactions. `vm.startBroadcast` only rewrites the `from` of the
     * transactions it wraps; it does not change what `msg.sender` evaluates
     * to as a plain expression in the script's own frame.
     *
     * This constructor argument used to read `msg.sender` and passed that
     * constant as the initial trusted evaluator, so the deployed guard's
     * `execute()` could never accept a signature from anyone: the address
     * has no discoverable private key. Fixed by deriving the deployer's own
     * address from its private key instead — still the deployer, as the
     * "for testing" comment intended, but the address actually broadcasting.
     *
     * The trusted evaluator can be pointed at a different, dedicated key
     * afterwards with `setTrustedEvaluator` (owner-only); the deployer is
     * only a safe placeholder, not a good long-term evaluator identity.
     */
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        AgentRegistry agentRegistry = new AgentRegistry();
        console.log("AgentRegistry deployed at:", address(agentRegistry));

        PolicyRegistry policyRegistry = new PolicyRegistry();
        console.log("PolicyRegistry deployed at:", address(policyRegistry));

        RiskAttestationRegistry attestationRegistry = new RiskAttestationRegistry();
        console.log("RiskAttestationRegistry deployed at:", address(attestationRegistry));

        ExecutionGuard executionGuard =
            new ExecutionGuard(address(agentRegistry), address(policyRegistry), address(attestationRegistry), deployer);
        console.log("ExecutionGuard deployed at:", address(executionGuard));
        console.log("Initial trusted evaluator (the deployer):", deployer);

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
