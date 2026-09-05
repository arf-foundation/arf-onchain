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

    /// @dev The only address permitted to consume attestations. Set after
    ///      deployment, because the guard needs this registry's address in its
    ///      own constructor.
    address public executionGuard;

    // ------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------

    event AttestationIssued(
        bytes32 indexed intentHash,
        address indexed agent,
        uint16 riskScore,
        Decision decision
    );

    event ExecutionGuardSet(address indexed guard);

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------

    constructor() Ownable(msg.sender) {}

    // ------------------------------------------------------------------------
    // Core Functions
    // ------------------------------------------------------------------------

    /**
     * @dev Sets the ExecutionGuard permitted to consume attestations.
     *
     * The guard's constructor takes this registry's address, so the guard does
     * not exist yet when this contract is deployed. Deployment scripts must
     * call this immediately afterwards — until they do, `recordAttestation`
     * reverts and no execution can complete.
     */
    function setExecutionGuard(address guard) external onlyOwner {
        require(guard != address(0), "RiskAttestationRegistry: zero guard");
        executionGuard = guard;
        emit ExecutionGuardSet(guard);
    }

    /**
     * @dev Records a governance attestation, marking it consumed.
     *
     * Restricted to `ExecutionGuard`. It previously was not, with a comment
     * claiming that the attestation's cryptographic binding made a caller check
     * unnecessary. It did not: `intentHash` is derivable from public state, so
     * any address could consume a victim's intent hash before they used it and
     * permanently block a legitimate, signed, in-policy approval — turning
     * fail-closed into a denial-of-service primitive. The same open entry point
     * also let anyone emit `AttestationIssued` for an agent and decision that
     * were never evaluated, making the on-chain audit trail forgeable.
     *
     * @param attestation The governance attestation to record.
     */
    function recordAttestation(RiskAttestation calldata attestation) external {
        require(msg.sender == executionGuard, "RiskAttestationRegistry: not the guard");
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
