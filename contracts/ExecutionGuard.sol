// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {AgentRegistry} from "./AgentRegistry.sol";
import {PolicyRegistry} from "./PolicyRegistry.sol";
import {RiskAttestationRegistry} from "./RiskAttestationRegistry.sol";
import {AttestationLib} from "./AttestationLib.sol";

/**
 * @title ExecutionGuard
 * @dev The security boundary for autonomous agent execution.
 *      Validates governance attestations before allowing any transaction to execute on Monad.
 *
 *      The evaluator signs the entire attestation as EIP-712 typed data. An
 *      earlier version signed only `attestation.intentHash`, which left
 *      `decision`, `riskScore`, `reversibility` and `modelHash` unauthenticated
 *      — a caller could take a validly signed DENY and execute it as an
 *      APPROVE. Signing the full struct binds the verdict to the transaction,
 *      and the EIP-712 domain additionally binds both to this chain and this
 *      contract.
 */
contract ExecutionGuard is Ownable, ReentrancyGuard, EIP712 {
    using ECDSA for bytes32;
    using AttestationLib for RiskAttestationRegistry.RiskAttestation;

    AgentRegistry public immutable agentRegistry;
    PolicyRegistry public immutable policyRegistry;
    RiskAttestationRegistry public immutable attestationRegistry;

    address public trustedEvaluator;

    event ExecutionApproved(bytes32 indexed intentHash, address indexed agent, address indexed target, uint256 value);

    event ExecutionDenied(bytes32 indexed intentHash, address indexed agent, uint256 riskScore, string reason);

    event ExecutionEscalated(bytes32 indexed intentHash, address indexed agent, uint256 riskScore);

    constructor(
        address _agentRegistry,
        address _policyRegistry,
        address _attestationRegistry,
        address _trustedEvaluator
    ) Ownable(msg.sender) EIP712("ARF Onchain", "1") {
        agentRegistry = AgentRegistry(_agentRegistry);
        policyRegistry = PolicyRegistry(_policyRegistry);
        attestationRegistry = RiskAttestationRegistry(_attestationRegistry);
        trustedEvaluator = _trustedEvaluator;
    }

    function setTrustedEvaluator(address _evaluator) external onlyOwner {
        trustedEvaluator = _evaluator;
    }

    function execute(
        address target,
        uint256 value,
        bytes calldata data,
        RiskAttestationRegistry.RiskAttestation calldata attestation,
        bytes calldata signature
    ) external nonReentrant {
        // 1. Verify agent exists and is active
        bytes32 agentId = keccak256(abi.encodePacked(attestation.agent));
        require(agentRegistry.isActive(agentId), "ExecutionGuard: agent inactive");

        // 2. Verify caller is authorized
        AgentRegistry.Agent memory agent = agentRegistry.getAgent(agentId);
        require(attestation.agent == msg.sender || agent.wallet == msg.sender, "ExecutionGuard: caller not authorized");

        // 3. Verify attestation not already used
        require(
            !attestationRegistry.isAttestationUsed(attestation.intentHash), "ExecutionGuard: attestation already used"
        );

        // 4. Verify evaluator is trusted
        require(attestation.evaluator == trustedEvaluator, "ExecutionGuard: untrusted evaluator");

        // 5. Verify the evaluator signed THIS attestation, in full.
        //    Covers decision, riskScore, reversibility and modelHash — not just
        //    the intent hash — so no field can be rewritten in transit.
        require(
            hashAttestation(attestation).recover(signature) == trustedEvaluator, "ExecutionGuard: invalid signature"
        );

        // 6. Verify expiry
        require(attestation.validUntil >= block.timestamp, "ExecutionGuard: attestation expired");

        // 7. Verify intent hash matches actual transaction
        bytes32 computedIntentHash = computeIntentHash(
            attestation.agent,
            target,
            value,
            data,
            attestation.policyHash,
            block.chainid,
            attestation.validUntil,
            agent.nonce
        );
        require(computedIntentHash == attestation.intentHash, "ExecutionGuard: intent hash mismatch");

        // 8. Verify policy is active (if policyHash is non-zero)
        if (attestation.policyHash != bytes32(0)) {
            require(policyRegistry.isPolicyActive(attestation.policyHash), "ExecutionGuard: policy inactive");
        }

        // 9. Process decision
        if (attestation.decision == RiskAttestationRegistry.Decision.APPROVE) {
            require(value <= agent.maxTransactionValue, "ExecutionGuard: exceeds per-tx limit");

            attestationRegistry.recordAttestation(attestation);

            (bool success,) = target.call{value: value}(data);
            require(success, "ExecutionGuard: execution failed");

            emit ExecutionApproved(attestation.intentHash, attestation.agent, target, value);
        } else if (attestation.decision == RiskAttestationRegistry.Decision.ESCALATE) {
            emit ExecutionEscalated(attestation.intentHash, attestation.agent, attestation.riskScore);
            revert("ExecutionGuard: ESCALATE requires human approval");
        } else if (attestation.decision == RiskAttestationRegistry.Decision.DENY) {
            emit ExecutionDenied(attestation.intentHash, attestation.agent, attestation.riskScore, "Decision DENY");
            revert("ExecutionGuard: execution denied by ARF");
        } else {
            revert("ExecutionGuard: unknown decision");
        }
    }

    /**
     * @dev The EIP-712 digest an evaluator must sign for `attestation`.
     *
     * Exposed so off-chain signers and auditors can confirm they are producing
     * the same digest this contract verifies, rather than reimplementing the
     * encoding and hoping it matches.
     */
    function hashAttestation(RiskAttestationRegistry.RiskAttestation memory attestation) public view returns (bytes32) {
        return _hashTypedDataV4(AttestationLib.hashStruct(attestation));
    }

    /// @dev The EIP-712 domain separator for this deployment.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function computeIntentHash(
        address agent,
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 policyHash,
        uint256 chainId,
        uint256 expiry,
        uint256 nonce
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(agent, target, value, data, policyHash, chainId, expiry, nonce));
    }
}
