// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AgentRegistry is Ownable {
    struct Agent {
        address wallet;
        address owner;
        uint256 maxTransactionValue;
        uint256 dailyLimit;
        bool active;
        uint256 nonce;
    }

    mapping(bytes32 => Agent) public agents;
    bytes32[] public agentIds;

    event AgentRegistered(bytes32 indexed agentId, address indexed wallet, address indexed owner);
    event AgentUpdated(bytes32 indexed agentId);
    event AgentDeactivated(bytes32 indexed agentId);

    constructor() Ownable(msg.sender) {}

    function registerAgent(
        bytes32 agentId,
        address wallet,
        address owner,
        uint256 maxTransactionValue,
        uint256 dailyLimit
    ) external onlyOwner {
        require(wallet != address(0), "AgentRegistry: zero wallet");
        require(owner != address(0), "AgentRegistry: zero owner");
        require(agents[agentId].wallet == address(0), "AgentRegistry: agent already exists");

        agents[agentId] = Agent({
            wallet: wallet,
            owner: owner,
            maxTransactionValue: maxTransactionValue,
            dailyLimit: dailyLimit,
            active: true,
            nonce: 0
        });
        agentIds.push(agentId);
        emit AgentRegistered(agentId, wallet, owner);
    }

    function getAgent(bytes32 agentId) external view returns (Agent memory) {
        return agents[agentId];
    }

    function isActive(bytes32 agentId) external view returns (bool) {
        return agents[agentId].active;
    }

    function updateAgent(bytes32 agentId, uint256 maxTx, uint256 dailyLimit) external onlyOwner {
        require(agents[agentId].wallet != address(0), "AgentRegistry: agent not found");
        agents[agentId].maxTransactionValue = maxTx;
        agents[agentId].dailyLimit = dailyLimit;
        emit AgentUpdated(agentId);
    }

    function deactivateAgent(bytes32 agentId) external onlyOwner {
        require(agents[agentId].wallet != address(0), "AgentRegistry: agent not found");
        agents[agentId].active = false;
        emit AgentDeactivated(agentId);
    }

    function incrementNonce(bytes32 agentId) external {
        require(msg.sender == agents[agentId].wallet || msg.sender == owner(), "AgentRegistry: not authorized");
        agents[agentId].nonce++;
    }
}
