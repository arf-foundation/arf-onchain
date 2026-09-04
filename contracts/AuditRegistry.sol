// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AuditRegistry is Ownable {
    struct AuditEntry {
        bytes32 intentHash;
        address agent;
        address target;
        uint256 value;
        uint16 riskScore;
        uint8 decision;
        uint8 reversibility;
        uint256 timestamp;
    }

    AuditEntry[] public auditLog;

    event AuditRecorded(
        bytes32 indexed intentHash,
        address indexed agent,
        uint16 riskScore,
        uint8 decision
    );

    constructor() Ownable(msg.sender) {}

    function record(
        bytes32 intentHash,
        address agent,
        address target,
        uint256 value,
        uint16 riskScore,
        uint8 decision,
        uint8 reversibility
    ) external onlyOwner {
        auditLog.push(AuditEntry({
            intentHash: intentHash,
            agent: agent,
            target: target,
            value: value,
            riskScore: riskScore,
            decision: decision,
            reversibility: reversibility,
            timestamp: block.timestamp
        }));
        emit AuditRecorded(intentHash, agent, riskScore, decision);
    }

    function getAuditCount() external view returns (uint256) {
        return auditLog.length;
    }

    function getAuditEntry(uint256 index) external view returns (AuditEntry memory) {
        return auditLog[index];
    }
}
