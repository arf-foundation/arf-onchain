// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";

contract RegisterAgentCorrect is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // NEW AgentRegistry address
        address agentRegistryAddr = 0x875f065F8D50bc657F3f9fa37cdB44Df3990EC88;
        AgentRegistry registry = AgentRegistry(agentRegistryAddr);

        // Compute the ID that ExecutionGuard will compute:
        bytes32 agentId = keccak256(abi.encodePacked(deployer));
        address agentWallet = deployer;
        address agentOwner = deployer;

        // Check if already registered
        (address wallet,,,, bool active,) = registry.agents(agentId);
        if (wallet != address(0)) {
            console.log("Agent already exists, skipping registration.");
            console.log("Agent ID:", vm.toString(agentId));
            return;
        }

        vm.startBroadcast(deployerPrivateKey);
        registry.registerAgent(agentId, agentWallet, agentOwner, 10000 ether, 50000 ether);
        vm.stopBroadcast();

        console.log("Agent registered with ID:", vm.toString(agentId));
        console.log("Agent wallet:", agentWallet);
    }
}
