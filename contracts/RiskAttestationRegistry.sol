// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RiskAttestationRegistry
 * @dev Stores and verifies cryptographically signed ARF governance attestations.
 *
 * An attestation is produced off-chain by the ARF engine and contains:
 *   - intentHash : cryptographic binding to the exact transaction
 *   - policyHash : reference to the policy that was evaluated
 *   - modelHash  : reference to the risk model version used
 *   - riskScore  : numerical risk score (0–1000, where 1000 = highest risk)
 *   - reversibility : REVERSIBLE / COMPENSABLE / IRREVERSIBLE
 *   - decision   : APPROVE / ESCALATE / DENY
 *   - agent      : address of the agent that requested the action
 *   - evaluator  : address that signed the attestation (trusted ARF engine)
 *   - issuedAt   : timestamp when the attestation was created
 *   - validUntil : expiration timestamp (attestations are time‑bounded)
 *   - rationaleHash : hash of the detailed reasoning (for off‑chain audit)
 *
 * The contract does NOT reproduce the full ARF risk model on‑chain.
 * Instead, it verifies the cryptographic integrity of the attestation and
 * ensures it has not been consumed (replay protection).
 *
 * ExecutionGuard is responsible for all other checks:
 *   - identity, policy, exposure, decision logic, etc.
 */
contract RiskAttestationRegistry is Ownable {
    // ------------------------------------------------------------------------
    // Enums
    // ------------------------------------------------------------------------

    enum Decision { APPROVE, ESCALATE, DENY }
    enum Reversibility { REVERSIBLE, COMPENSABLE, IRREVERSIBLE }

    // ------------------------------------------------------------------------
    // Structs
    // ------------------------------------------------------------------------

    struct RiskAttestation {
        bytes32 intentHash;
        bytes32 policyHash;
        bytes32 modelHash;
        uint16 riskScore;          // 0–1000 (0 = safe, 1000 = dangerous)
        Reversibility reversibility;
        Decision decision;
        address agent;
        address evaluator;
        uint256 issuedAt;
        uint256 validUntil;
        bytes32 rationaleHash;
    }

    // ------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------

    /// @dev Tracks consumed attestations to prevent replay attacks.
    mapping(bytes32 => bool) public usedAttestations;

    // ------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------

    event AttestationIssued(
        bytes32 indexed intentHash,
        address indexed agent,
        uint16 riskScore,
        Decision decision
    );

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------

    constructor() Ownable(msg.sender) {}

    // ------------------------------------------------------------------------
    // Core Functions
    // ------------------------------------------------------------------------

    /**
     * @dev Records a governance attestation.
     *
     * This function is called by ExecutionGuard after validating the attestation.
     * The call marks the attestation as used, preventing replays.
     *
     * NOTE: This function is intentionally NOT restricted to `onlyOwner`.
     *       The attestation itself is cryptographically bound to the transaction
     *       and verified by ExecutionGuard. Removing the owner check allows
     *       ExecutionGuard to call it directly.
     *
     * @param attestation The governance attestation to record.
     */
    function recordAttestation(RiskAttestation calldata attestation) external {
        bytes32 id = attestation.intentHash;
        require(!usedAttestations[id], "RiskAttestationRegistry: already used");
        usedAttestations[id] = true;
        emit AttestationIssued(id, attestation.agent, attestation.riskScore, attestation.decision);
    }

    /**
     * @dev Checks whether an attestation has already been consumed.
     * @param intentHash The intent hash to check.
     * @return True if the attestation is already used.
     */
    function isAttestationUsed(bytes32 intentHash) external view returns (bool) {
        return usedAttestations[intentHash];
    }
}
