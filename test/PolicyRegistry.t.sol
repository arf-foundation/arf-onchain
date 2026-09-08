// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {PolicyRegistry} from "../contracts/PolicyRegistry.sol";

/**
 * @title PolicyRegistryTest
 * @dev Direct unit tests. Everything else in the suite exercises this
 *      contract only indirectly through `ExecutionGuard`/`GuardHarness` --
 *      worth its own file for the same reason `AgentRegistry.t.sol` exists
 *      separately: a property of the registry itself (here, that zero can
 *      never become an active hash) should not depend on the guard's
 *      control flow ever reaching it.
 */
contract PolicyRegistryTest is Test {
    PolicyRegistry public registry;

    address public constant OWNER = address(0x123);
    address public constant ATTACKER = address(0xBAD);

    function setUp() public {
        vm.prank(OWNER);
        registry = new PolicyRegistry();
    }

    // ------------------------------------------------------------------
    // The zero-hash reservation
    // ------------------------------------------------------------------

    /// @dev The property this test suite exists to prove: not merely that
    ///      nothing registers zero today, but that nothing ever can.
    function test_ZeroHashCanNeverBeRegistered() public {
        vm.prank(OWNER);
        vm.expectRevert("PolicyRegistry: zero hash is reserved");
        registry.setPolicy(bytes32(0), "an owner mistake, or a script bug");

        assertFalse(registry.isPolicyActive(bytes32(0)), "zero must never read as active");
    }

    /// @dev A non-zero hash is unaffected by the reservation.
    function test_NonZeroHashRegistersNormally() public {
        bytes32 h = keccak256("real-policy-v1");

        vm.prank(OWNER);
        registry.setPolicy(h, "a real policy");

        assertTrue(registry.isPolicyActive(h));
    }

    function test_OnlyOwnerCanSetAPolicy() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        registry.setPolicy(keccak256("attacker-policy"), "should not register");
    }

    // ------------------------------------------------------------------
    // Activation lifecycle
    // ------------------------------------------------------------------

    function test_UnregisteredHashIsNotActive() public view {
        assertFalse(registry.isPolicyActive(keccak256("never-registered")));
    }

    function test_DeactivatingAPolicyMakesItInactive() public {
        bytes32 h = keccak256("temp-policy");
        vm.startPrank(OWNER);
        registry.setPolicy(h, "temporary");
        registry.deactivatePolicy(h);
        vm.stopPrank();

        assertFalse(registry.isPolicyActive(h));
    }

    function test_DeactivatingAnAlreadyInactivePolicyReverts() public {
        bytes32 h = keccak256("never-set");
        vm.prank(OWNER);
        vm.expectRevert("PolicyRegistry: policy not active");
        registry.deactivatePolicy(h);
    }

    function test_ReRegisteringReactivatesADeactivatedPolicy() public {
        bytes32 h = keccak256("cycled-policy");
        vm.startPrank(OWNER);
        registry.setPolicy(h, "v1");
        registry.deactivatePolicy(h);
        assertFalse(registry.isPolicyActive(h));

        registry.setPolicy(h, "v1, re-registered");
        vm.stopPrank();

        assertTrue(registry.isPolicyActive(h));
    }
}
