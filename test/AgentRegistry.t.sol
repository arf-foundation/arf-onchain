// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";

/**
 * @title AgentRegistryTest
 * @dev Unit tests for the AgentRegistry contract.
 *      Covers registration, duplication prevention, deactivation, authorization, and nonce management.
 */
contract AgentRegistryTest is Test {
    // ------------------------------------------------------------------------
    // State & Constants
    // ------------------------------------------------------------------------

    AgentRegistry public registry;

    address public constant OWNER = address(0x123);
    bytes32 public constant AGENT_ID = keccak256("agent-01");
    address public constant WALLET = address(0x456);
    address public constant AGENT_OWNER = address(0x789);

    // Lint suppression: define reusable constants instead of repeating literals.
    uint256 public constant MAX_TX = 10000 ether;
    uint256 public constant DAILY_LIMIT = 50000 ether;

    // ------------------------------------------------------------------------
    // Setup
    // ------------------------------------------------------------------------

    function setUp() public {
        vm.prank(OWNER);
        registry = new AgentRegistry();
    }

    // ------------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------------

    /// @dev Registers a valid agent and verifies stored fields.
    function testRegisterAgent() public {
        vm.prank(OWNER);
        registry.registerAgent(AGENT_ID, WALLET, AGENT_OWNER, MAX_TX, DAILY_LIMIT);

        (address returnedWallet, address returnedOwner, uint256 maxTx, uint256 dailyLimit, bool active, uint256 nonce) =
            registry.agents(AGENT_ID);

        assertEq(returnedWallet, WALLET, "wallet mismatch");
        assertEq(returnedOwner, AGENT_OWNER, "owner mismatch");
        assertEq(maxTx, MAX_TX, "maxTx mismatch");
        assertEq(dailyLimit, DAILY_LIMIT, "dailyLimit mismatch");
        assertTrue(active, "agent should be active");
        assertEq(nonce, 0, "initial nonce should be 0");
    }

    /// @dev Prevents registering the same agent ID twice.
    function testCannotRegisterTwice() public {
        vm.prank(OWNER);
        registry.registerAgent(AGENT_ID, WALLET, AGENT_OWNER, 0, 0);

        vm.prank(OWNER);
        vm.expectRevert("AgentRegistry: agent already exists");
        registry.registerAgent(AGENT_ID, WALLET, AGENT_OWNER, 0, 0);
    }

    /// @dev Deactivating an agent makes it inactive.
    function testDeactivateAgent() public {
        vm.prank(OWNER);
        registry.registerAgent(AGENT_ID, WALLET, AGENT_OWNER, 0, 0);

        vm.prank(OWNER);
        registry.deactivateAgent(AGENT_ID);
        assertFalse(registry.isActive(AGENT_ID), "agent should be inactive");
    }

    /// @dev Only the contract owner may register new agents.
    function testOnlyOwnerCanRegister() public {
        // Non-owner attempts to register; should revert.
        vm.prank(address(0x999));
        vm.expectRevert(); // Ownable's onlyOwner modifier will revert
        registry.registerAgent(AGENT_ID, WALLET, AGENT_OWNER, 0, 0);
    }

    /// @dev The agent's wallet can increment its nonce; this is used for replay protection.
    function testIncrementNonce() public {
        vm.prank(OWNER);
        registry.registerAgent(AGENT_ID, WALLET, AGENT_OWNER, 0, 0);

        // Only the wallet or the owner can increment the nonce.
        vm.prank(WALLET);
        registry.incrementNonce(AGENT_ID);

        (,,,,, uint256 nonce) = registry.agents(AGENT_ID);
        assertEq(nonce, 1, "nonce should be incremented to 1");
    }
}
