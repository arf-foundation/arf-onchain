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

    /**
     * @dev The id for an agent address.
     *
     * `ExecutionGuard.execute()` derives the id it looks up as
     * `keccak256(abi.encodePacked(attestation.agent))` and accepts no id from
     * the caller, so this is the only id that can ever reach a registered
     * agent. Exposed as a function because callers previously had to know the
     * derivation and get it right by hand.
     */
    function agentIdFor(address wallet) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(wallet));
    }

    /**
     * @dev Registers an agent under the id the guard will look for.
     *
     * The id used to be a parameter. It could therefore be anything, and an
     * agent registered under any id but `agentIdFor(wallet)` was silently
     * unreachable: registration succeeded, the agent appeared in the registry,
     * and every `execute()` reverted with "agent inactive" because the guard
     * looked up a different key. `script/RegisterAgent.s.sol` did exactly this
     * with `keccak256("treasury-agent-01")`, which is why a second script
     * existed alongside it whose only distinguishing feature was computing the
     * id correctly.
     *
     * Deriving it here makes the unreachable registration unrepresentable.
     *
     * @return agentId The derived id, so callers need not recompute it.
     */
    function registerAgent(address wallet, address owner, uint256 maxTransactionValue, uint256 dailyLimit)
        external
        onlyOwner
        returns (bytes32 agentId)
    {
        require(wallet != address(0), "AgentRegistry: zero wallet");
        require(owner != address(0), "AgentRegistry: zero owner");
        agentId = agentIdFor(wallet);
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
