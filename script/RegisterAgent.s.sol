// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";

/**
 * @title RegisterAgent
 * @dev Registers an agent under the id `ExecutionGuard` will look up.
 *
 * There used to be two of these scripts. The first passed
 * `keccak256("treasury-agent-01")` as the agent id, which registered an agent
 * that no `execute()` call could ever resolve — the guard derives the id from
 * the agent address and accepts no other. The second existed solely to compute
 * the id correctly, and the registry address in each pointed at a different
 * deployment.
 *
 * `AgentRegistry.registerAgent` now derives the id itself, so there is one
 * script and no id to get wrong.
 *
 * The registry address is read from the environment rather than hardcoded:
 * a stale literal is how the two scripts came to disagree about which
 * deployment they were configuring.
 */
contract RegisterAgent is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address registryAddress = vm.envAddress("AGENT_REGISTRY_ADDRESS");
        address agentWallet = vm.envOr("AGENT_WALLET", vm.addr(deployerPrivateKey));
        address agentOwner = vm.envOr("AGENT_OWNER", agentWallet);

        uint256 maxTransactionValue = vm.envOr("AGENT_MAX_TX_WEI", uint256(10_000 ether));
        uint256 dailyLimit = vm.envOr("AGENT_DAILY_LIMIT_WEI", uint256(50_000 ether));

        AgentRegistry registry = AgentRegistry(registryAddress);
        bytes32 agentId = registry.agentIdFor(agentWallet);

        (address existingWallet,,,,,) = registry.agents(agentId);
        if (existingWallet != address(0)) {
            console.log("Agent already registered; nothing to do.");
            console.log("  agentId:", vm.toString(agentId));
            console.log("  wallet: ", existingWallet);
            return;
        }

        vm.startBroadcast(deployerPrivateKey);
        registry.registerAgent(agentWallet, agentOwner, maxTransactionValue, dailyLimit);
        vm.stopBroadcast();

        console.log("Agent registered.");
        console.log("  agentId:", vm.toString(agentId));
        console.log("  wallet: ", agentWallet);
        console.log("  owner:  ", agentOwner);
    }
}
