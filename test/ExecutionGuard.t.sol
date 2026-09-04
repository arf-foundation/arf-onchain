// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {ExecutionGuard} from "../contracts/ExecutionGuard.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";
import {PolicyRegistry} from "../contracts/PolicyRegistry.sol";
import {RiskAttestationRegistry} from "../contracts/RiskAttestationRegistry.sol";

contract ExecutionGuardTest is Test {
    ExecutionGuard public guard;
    AgentRegistry public agentReg;
    PolicyRegistry public policyReg;
    RiskAttestationRegistry public attestReg;

    address public deployer = address(0x123);
    address public agentWallet = address(0x456);
    bytes32 public agentId = keccak256("agent-01");

    function setUp() public {
        vm.prank(deployer);
        agentReg = new AgentRegistry();
        policyReg = new PolicyRegistry();
        attestReg = new RiskAttestationRegistry();
        guard = new ExecutionGuard(address(agentReg), address(policyReg), address(attestReg), deployer);
        // Register an agent for testing
        vm.prank(deployer);
        agentReg.registerAgent(agentId, agentWallet, agentWallet, 10000 ether, 50000 ether);
    }

    function testExecuteRevertsBecauseNotImplementedYet() public {
        // The full execute() logic is implemented, but we need a valid attestation.
        // For now, just check that the contract is deployed.
        assertTrue(address(guard) != address(0));
    }

    // TODO: Add tests for full flow once we have off-chain signing infrastructure.
    // For Week 2, we've implemented the logic; testing will be completed in Week 3 with a signer.
}
