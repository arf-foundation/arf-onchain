// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RiskAttestationRegistry is Ownable {
    enum Decision { APPROVE, ESCALATE, DENY }
    enum Reversibility { REVERSIBLE, COMPENSABLE, IRREVERSIBLE }

    struct RiskAttestation {
        bytes32 intentHash;
        bytes32 policyHash;
        bytes32 modelHash;
        uint16 riskScore;
        Reversibility reversibility;
        Decision decision;
        address agent;
        address evaluator;
        uint256 issuedAt;
        uint256 validUntil;
        bytes32 rationaleHash;
    }

    mapping(bytes32 => bool) public usedAttestations;

    event AttestationIssued(
        bytes32 indexed intentHash,
        address indexed agent,
        uint16 riskScore,
        Decision decision
    );

    event AttestationUsed(bytes32 indexed intentHash);

    constructor() Ownable(msg.sender) {}

    function recordAttestation(RiskAttestation calldata attestation) external onlyOwner {
        bytes32 id = attestation.intentHash;
        require(!usedAttestations[id], "RiskAttestationRegistry: already used");
        usedAttestations[id] = true;
        emit AttestationIssued(id, attestation.agent, attestation.riskScore, attestation.decision);
    }

    function isAttestationUsed(bytes32 intentHash) external view returns (bool) {
        return usedAttestations[intentHash];
    }
}
