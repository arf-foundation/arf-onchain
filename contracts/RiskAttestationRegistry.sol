// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @dev The subset of `ExecutionGuard` this registry needs.
 *
 * Declared as an interface rather than imported to avoid a circular import:
 * the guard already imports this file. The digest must come from the guard
 * because the EIP-712 domain binds to the guard's own address — computing it
 * here would produce a different digest, and one signature could not serve
 * both anchoring and execution.
 */
interface IExecutionGuardDigest {
    function hashAttestation(RiskAttestationRegistry.RiskAttestation memory attestation)
        external
        view
        returns (bytes32);

    function trustedEvaluator() external view returns (address);
}

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

    enum Decision {
        APPROVE,
        ESCALATE,
        DENY
    }
    enum Reversibility {
        REVERSIBLE,
        COMPENSABLE,
        IRREVERSIBLE,
        UNDETERMINED
    }

    // ------------------------------------------------------------------------
    // Structs
    // ------------------------------------------------------------------------

    struct RiskAttestation {
        bytes32 intentHash;
        bytes32 policyHash;
        bytes32 modelHash;
        uint16 riskScore; // 0–1000 (0 = safe, 1000 = dangerous)
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
    ///      Keyed by `intentHash`: one intent may be executed once.
    mapping(bytes32 => bool) public usedAttestations;

    /// @dev Tracks anchored decisions, keyed by EIP-712 digest rather than by
    ///      `intentHash`. Deliberately a different key and a different mapping
    ///      from `usedAttestations`.
    ///
    ///      Different mapping, because anchoring must not consume: anchoring a
    ///      DENY would otherwise permanently block the later, legitimate retry
    ///      that follows remediation, and anchoring an APPROVE would brick the
    ///      execution it was meant to record.
    ///
    ///      Different key, because the digest covers the whole verdict. Two
    ///      decisions about the same intent — denied at first, approved after
    ///      the operator took a backup — are distinct records, and an audit
    ///      trail that could only hold one of them would lose the sequence that
    ///      makes it worth reading.
    mapping(bytes32 => bool) public anchoredDecisions;

    /// @dev The only address permitted to consume attestations. Set after
    ///      deployment, because the guard needs this registry's address in its
    ///      own constructor.
    address public executionGuard;

    // ------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------

    event AttestationIssued(bytes32 indexed intentHash, address indexed agent, uint16 riskScore, Decision decision);

    event ExecutionGuardSet(address indexed guard);

    /**
     * @dev A governance decision, recorded whatever the verdict.
     *
     * `AttestationIssued` only ever fires for approvals, because it is emitted
     * from the execution path and a denied execution reverts. That makes the
     * on-chain history a log of what ran, not a log of what was decided — and
     * the decisions worth proving after the fact are precisely the ones where
     * the governance layer refused.
     */
    event DecisionAnchored(
        bytes32 indexed digest,
        bytes32 indexed intentHash,
        address indexed agent,
        Decision decision,
        Reversibility reversibility,
        uint16 riskScore,
        bytes32 rationaleHash
    );

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
     * @dev Records a governance decision on-chain without executing anything.
     *
     * This is the audit trail. `recordAttestation` runs only inside a
     * successful execution, so before this existed the chain held approvals and
     * nothing else: a DENY reverts, and a reverted transaction emits no logs,
     * so `ExecutionGuard`'s denial events could never appear in any receipt.
     * The one governance outcome anybody needs to prove — that the system
     * refused — left no trace at all.
     *
     * Permissionless by design. The evaluator's signature is the authorisation,
     * so anyone holding a genuine decision may publish it: the agent, the
     * operator, an auditor, or ARF. Nobody can forge one, and nobody can
     * suppress one by declining to submit it.
     *
     * Anchoring does not consume the attestation. A denial anchored here does
     * not block the retry that follows remediation, and an approval anchored
     * here still executes.
     *
     * @param attestation The decision to record.
     * @param signature   The evaluator's EIP-712 signature over `attestation`.
     */
    function anchorDecision(RiskAttestation calldata attestation, bytes calldata signature) external {
        require(executionGuard != address(0), "RiskAttestationRegistry: guard not set");

        IExecutionGuardDigest guard = IExecutionGuardDigest(executionGuard);
        bytes32 digest = guard.hashAttestation(attestation);

        // The guard's trusted evaluator is the single source of truth for who
        // may issue decisions. Reading it here rather than keeping a second
        // copy means rotating the evaluator cannot leave the two disagreeing.
        address expected = guard.trustedEvaluator();
        require(attestation.evaluator == expected, "RiskAttestationRegistry: untrusted evaluator");
        require(ECDSA.recover(digest, signature) == expected, "RiskAttestationRegistry: invalid signature");

        require(!anchoredDecisions[digest], "RiskAttestationRegistry: already anchored");
        anchoredDecisions[digest] = true;

        emit DecisionAnchored(
            digest,
            attestation.intentHash,
            attestation.agent,
            attestation.decision,
            attestation.reversibility,
            attestation.riskScore,
            attestation.rationaleHash
        );
    }

    /**
     * @dev Checks whether an attestation has already been consumed.
     * @param intentHash The intent hash to check.
     * @return True if the attestation is already used.
     */
    function isAttestationUsed(bytes32 intentHash) external view returns (bool) {
        return usedAttestations[intentHash];
    }

    /**
     * @dev Checks whether a decision has already been anchored.
     * @param digest The EIP-712 digest of the attestation.
     * @return True if the decision is already on the record.
     */
    function isDecisionAnchored(bytes32 digest) external view returns (bool) {
        return anchoredDecisions[digest];
    }
}
