// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";

/**
 * @title AgentRegistryTest
 * @dev Registration, duplication, deactivation, authorisation and nonces.
 *
 * These tests previously registered agents under `keccak256("agent-01")` and
 * asserted the stored fields came back. They all passed. They could not fail:
 * nothing here calls `ExecutionGuard.execute()`, which is the only place the id
 * derivation matters, and an agent registered under an id the guard never
 * computes is invisible rather than broken.
 *
 * The registry now derives the id, so the mismatch is unrepresentable. The
 * tests use the derived id to say so.
 */
contract AgentRegistryTest is Test {
    AgentRegistry public registry;

    address public constant OWNER = address(0x123);
    address public constant WALLET = address(0x456);
    address public constant AGENT_OWNER = address(0x789);

    uint256 public constant MAX_TX = 10000 ether;
    uint256 public constant DAILY_LIMIT = 50000 ether;

    bytes32 public agentId;

    function setUp() public {
        vm.prank(OWNER);
        registry = new AgentRegistry();
        agentId = registry.agentIdFor(WALLET);
    }

    // ------------------------------------------------------------------
    // Identity
    // ------------------------------------------------------------------

    /**
     * @dev The regression. `ExecutionGuard.execute()` looks up
     *      `keccak256(abi.encodePacked(attestation.agent))`, so registration
     *      must produce that id and nothing else.
     */
    function test_RegistrationUsesTheIdTheGuardDerives() public {
        vm.prank(OWNER);
        bytes32 returned = registry.registerAgent(WALLET, AGENT_OWNER, MAX_TX, DAILY_LIMIT);

        assertEq(returned, keccak256(abi.encodePacked(WALLET)), "id is not the guard's derivation");
        assertTrue(registry.isActive(returned), "the derived id does not resolve to the agent");
    }

    function test_AgentIdForMatchesTheGuardsDerivation() public view {
        assertEq(registry.agentIdFor(WALLET), keccak256(abi.encodePacked(WALLET)));
    }

    // ------------------------------------------------------------------
    // Registration
    // ------------------------------------------------------------------

    function testRegisterAgent() public {
        vm.prank(OWNER);
        registry.registerAgent(WALLET, AGENT_OWNER, MAX_TX, DAILY_LIMIT);

        (address returnedWallet, address returnedOwner, uint256 maxTx, uint256 dailyLimit, bool active, uint256 nonce) =
            registry.agents(agentId);

        assertEq(returnedWallet, WALLET, "wallet mismatch");
        assertEq(returnedOwner, AGENT_OWNER, "owner mismatch");
        assertEq(maxTx, MAX_TX, "maxTx mismatch");
        assertEq(dailyLimit, DAILY_LIMIT, "dailyLimit mismatch");
        assertTrue(active, "agent should be active");
        assertEq(nonce, 0, "initial nonce should be 0");
    }

    /// @dev One wallet is one agent: the id is a function of the wallet, so a
    ///      second registration for the same wallet necessarily collides.
    function testCannotRegisterTwice() public {
        vm.prank(OWNER);
        registry.registerAgent(WALLET, AGENT_OWNER, 0, 0);

        vm.prank(OWNER);
        vm.expectRevert("AgentRegistry: agent already exists");
        registry.registerAgent(WALLET, AGENT_OWNER, 0, 0);
    }

    function test_ZeroWalletIsRefused() public {
        vm.prank(OWNER);
        vm.expectRevert("AgentRegistry: zero wallet");
        registry.registerAgent(address(0), AGENT_OWNER, 0, 0);
    }

    function testOnlyOwnerCanRegister() public {
        vm.prank(address(0x999));
        vm.expectRevert();
        registry.registerAgent(WALLET, AGENT_OWNER, 0, 0);
    }

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    function testDeactivateAgent() public {
        vm.prank(OWNER);
        registry.registerAgent(WALLET, AGENT_OWNER, 0, 0);

        vm.prank(OWNER);
        registry.deactivateAgent(agentId);
        assertFalse(registry.isActive(agentId), "agent should be inactive");
    }

    function testIncrementNonce() public {
        vm.prank(OWNER);
        registry.registerAgent(WALLET, AGENT_OWNER, 0, 0);

        vm.prank(WALLET);
        registry.incrementNonce(agentId);

        (,,,,, uint256 nonce) = registry.agents(agentId);
        assertEq(nonce, 1, "nonce should be incremented to 1");
    }
}
