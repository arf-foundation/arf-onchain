// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {RiskAttestationRegistry} from "./RiskAttestationRegistry.sol";

/**
 * @title AttestationLib
 * @dev The canonical EIP-712 encoding of a governance attestation.
 *
 * This exists so there is exactly one definition of what the evaluator signs.
 * Before this library, `ExecutionGuard` recovered the evaluator's signature
 * over `attestation.intentHash` alone — and `intentHash` binds only
 * (agent, target, value, data, policyHash, chainId, expiry, nonce). Every other
 * field of the attestation, `decision` included, arrived as unauthenticated
 * calldata, so a caller holding a signed DENY could resubmit it as an APPROVE.
 *
 * Hashing the whole struct closes that: changing any field invalidates the
 * signature. Because EIP-712's domain separator also covers the chain id and
 * the verifying contract, an attestation additionally cannot be replayed onto
 * another chain or against a different `ExecutionGuard` deployment.
 *
 * Off-chain signers must reproduce `ATTESTATION_TYPE` exactly — field order,
 * types, and the absence of whitespace are all part of the hash.
 */
library AttestationLib {
    /// @dev The EIP-712 type string. Enums are encoded as `uint8`.
    string internal constant ATTESTATION_TYPE = "RiskAttestation("
        "bytes32 intentHash,"
        "bytes32 policyHash,"
        "bytes32 modelHash,"
        "uint16 riskScore,"
        "uint8 reversibility,"
        "uint8 decision,"
        "address agent,"
        "address evaluator,"
        "uint256 issuedAt,"
        "uint256 validUntil,"
        "bytes32 rationaleHash)";

    bytes32 internal constant ATTESTATION_TYPEHASH = keccak256(bytes(ATTESTATION_TYPE));

    /**
     * @dev EIP-712 `hashStruct` for an attestation.
     *
     * Every field is included. If a field is ever added to
     * `RiskAttestationRegistry.RiskAttestation`, it must be added here and to
     * `ATTESTATION_TYPE`, or it will be signable-around.
     */
    function hashStruct(RiskAttestationRegistry.RiskAttestation memory a) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ATTESTATION_TYPEHASH,
                a.intentHash,
                a.policyHash,
                a.modelHash,
                a.riskScore,
                uint8(a.reversibility),
                uint8(a.decision),
                a.agent,
                a.evaluator,
                a.issuedAt,
                a.validUntil,
                a.rationaleHash
            )
        );
    }
}
