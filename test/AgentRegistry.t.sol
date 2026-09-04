// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";

contract AgentRegistryTest is Test {
    AgentRegistry public registry;
    address public owner = address(0x123);
    bytes32 public agentId = keccak256("agent-01");
    address public wallet = address(0x456);
    address public agentOwner = address(0x789);

    function setUp() public {
        vm.prank(owner);
        registry = new AgentRegistry();
    }

    function testRegisterAgent() public {
        vm.prank(owner);
        registry.registerAgent(
            agentId,
            wallet,
            agentOwner,
            10000 ether,
            50000 ether
        );

        (address returnedWallet, address returnedOwner, uint256 maxTx, uint256 dailyLimit, bool active, uint256 nonce) = registry.agents(agentId);
        assertEq(returnedWallet, wallet);
        assertEq(returnedOwner, agentOwner);
        assertEq(maxTx, 10000 ether);
        assertEq(dailyLimit, 50000 ether);
        assertTrue(active);
        assertEq(nonce, 0);
    }

    function testCannotRegisterTwice() public {
        vm.prank(owner);
        registry.registerAgent(agentId, wallet, agentOwner, 0, 0);
        vm.expectRevert("AgentRegistry: agent already exists");
        vm.prank(owner);
        registry.registerAgent(agentId, wallet, agentOwner, 0, 0);
    }

    function testDeactivateAgent() public {
        vm.prank(owner);
        registry.registerAgent(agentId, wallet, agentOwner, 0, 0);
        vm.prank(owner);
        registry.deactivateAgent(agentId);
        assertFalse(registry.isActive(agentId));
    }

    function testOnlyOwnerCanRegister() public {
        vm.prank(address(0x999));
        vm.expectRevert();
        registry.registerAgent(agentId, wallet, agentOwner, 0, 0);
    }

    function testIncrementNonce() public {
        vm.prank(owner);
        registry.registerAgent(agentId, wallet, agentOwner, 0, 0);
        
        vm.prank(wallet);
        registry.incrementNonce(agentId);
        
        (, , , , , uint256 nonce) = registry.agents(agentId);
        assertEq(nonce, 1);
    }
}
