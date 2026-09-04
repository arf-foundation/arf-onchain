// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";

contract RegisterAgent is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Replace with your deployed AgentRegistry address
        address agentRegistryAddr = 0x7C17981030399d0b51b097a9483e60df8F3ce7A7;
        AgentRegistry registry = AgentRegistry(agentRegistryAddr);

        bytes32 agentId = keccak256("treasury-agent-01");
        address agentWallet = vm.addr(deployerPrivateKey); // deployer as agent wallet
        address agentOwner = agentWallet;

        registry.registerAgent(
            agentId,
            agentWallet,
            agentOwner,
            10000 ether, // max tx: 10,000 MON
            50000 ether  // daily limit: 50,000 MON
        );

        console.log("Agent registered with ID:", vm.toString(agentId));
        console.log("Agent wallet:", agentWallet);
        console.log("Agent owner:", agentOwner);

        vm.stopBroadcast();
    }
}
