// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";
import {PolicyRegistry} from "../contracts/PolicyRegistry.sol";
import {RiskAttestationRegistry} from "../contracts/RiskAttestationRegistry.sol";
import {ExecutionGuard} from "../contracts/ExecutionGuard.sol";
import {AttestationLib} from "../contracts/AttestationLib.sol";

/**
 * @title OffchainSignatureTest
 * @dev The cross-language contract between these contracts and the off-chain
 *      evaluator that signs for them.
 *
 * An attestation is produced off-chain and verified here. Nothing about that
 * arrangement fails loudly when the two sides disagree: a signer whose encoding
 * differs by one byte produces a signature that recovers to some unrelated
 * address, and the guard rejects it as an untrusted evaluator. The symptom is
 * "invalid signature" — which looks like a key problem and is not.
 *
 * So the encoding is pinned on both sides. The vectors below are produced by
 * `arf_enterprise.onchain.attestation` and asserted identical here; the same
 * constants are asserted in `tests/test_onchain_attestation.py`. A change to
 * either encoding fails both suites instead of silently breaking issuance.
 *
 * The fixture key is a well-known test value and signs nothing outside tests.
 */
contract OffchainSignatureTest is Test {
    // ------------------------------------------------------------------
    // Fixture — identical to the Python suite's
    // ------------------------------------------------------------------

    uint256 internal constant FIXTURE_PK = 0x1111111111111111111111111111111111111111111111111111111111111111;

    address internal constant FIXTURE_AGENT = 0x00000000000000000000000000000000000000A1;
    address internal constant FIXTURE_GUARD = 0x00000000000000000000000000000000000000b2;
    address internal constant FIXTURE_TARGET = 0x00000000000000000000000000000000000000C3;
    uint256 internal constant FIXTURE_CHAIN_ID = 10143;

    bytes32 internal constant FIXTURE_INTENT = 0x1111111111111111111111111111111111111111111111111111111111111111;
    bytes32 internal constant FIXTURE_POLICY = 0x2222222222222222222222222222222222222222222222222222222222222222;
    bytes32 internal constant FIXTURE_MODEL = 0x3333333333333333333333333333333333333333333333333333333333333333;
    bytes32 internal constant FIXTURE_RATIONALE = 0x4444444444444444444444444444444444444444444444444444444444444444;

    uint256 internal constant FIXTURE_ISSUED_AT = 1_760_000_000;
    uint256 internal constant FIXTURE_VALID_UNTIL = 1_760_003_600;
    uint16 internal constant FIXTURE_RISK = 940;

    // ------------------------------------------------------------------
    // Pinned vectors — see tests/test_onchain_attestation.py
    // ------------------------------------------------------------------

    bytes32 internal constant PINNED_TYPE_HASH = 0x9f400ed18a3f2ae82df4934e927f1d22c8bd69646de106f8e312828a07efc01a;
    bytes32 internal constant PINNED_INTENT_HASH = 0x8ee1b7d7c35fb573932214285070757d6cf312774d63a0a33400563277243679;
    bytes32 internal constant PINNED_DOMAIN_SEPARATOR =
        0x63bbef83c78e9847da6e2e5a45f17e81251c68aceee4da063795afcb4d7c6d7f;
    bytes32 internal constant PINNED_HASH_STRUCT = 0x85cca2e6a8f65d5527fa3f2149ee6f7ed4490f1da687ca7d1649721f27c3715d;
    bytes32 internal constant PINNED_DIGEST = 0x968f23c17134eb9fc6da3357b2b8d3587e4967b57dbae2b342cbd0573960b412;

    /// @dev Produced by the Python signer for PINNED_DIGEST.
    bytes internal constant PINNED_SIGNATURE =
        hex"633cf1ce0bfea89ebdf06c5e670017633c136e1294b2a7d808d70c5d128f8705"
        hex"487fb3f035b3c426bbb13d84586f96f9a0f105e843feef5fb9b856ea0ea6c8db"
        hex"1c";

    ExecutionGuard internal guard;

    function setUp() public {
        AgentRegistry agentRegistry = new AgentRegistry();
        PolicyRegistry policyRegistry = new PolicyRegistry();
        RiskAttestationRegistry attestationRegistry = new RiskAttestationRegistry();
        guard = new ExecutionGuard(
            address(agentRegistry), address(policyRegistry), address(attestationRegistry), vm.addr(FIXTURE_PK)
        );
    }

    function fixtureAttestation() internal pure returns (RiskAttestationRegistry.RiskAttestation memory) {
        return RiskAttestationRegistry.RiskAttestation({
            intentHash: FIXTURE_INTENT,
            policyHash: FIXTURE_POLICY,
            modelHash: FIXTURE_MODEL,
            riskScore: FIXTURE_RISK,
            reversibility: RiskAttestationRegistry.Reversibility.IRREVERSIBLE,
            decision: RiskAttestationRegistry.Decision.DENY,
            agent: FIXTURE_AGENT,
            evaluator: 0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A,
            issuedAt: FIXTURE_ISSUED_AT,
            validUntil: FIXTURE_VALID_UNTIL,
            rationaleHash: FIXTURE_RATIONALE
        });
    }

    /// @dev The EIP-712 domain separator for an arbitrary chain and contract.
    ///      Written out rather than read from the guard so that this test
    ///      checks the *formula* the Python side reimplements, not just that
    ///      the guard agrees with itself.
    function domainSeparatorFor(uint256 chainId, address verifyingContract) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ARF Onchain")),
                keccak256(bytes("1")),
                chainId,
                verifyingContract
            )
        );
    }

    // ------------------------------------------------------------------
    // The type string
    // ------------------------------------------------------------------

    /// @dev Catches a type string that hashes consistently on each side while
    ///      describing different structs. No amount of Python-only testing can
    ///      find this, because both Python paths read the same definition.
    function test_TypeHashMatchesOffchain() public pure {
        assertEq(AttestationLib.ATTESTATION_TYPEHASH, PINNED_TYPE_HASH, "ATTESTATION_TYPE diverged from the signer");
    }

    // ------------------------------------------------------------------
    // The struct encoding
    // ------------------------------------------------------------------

    function test_HashStructMatchesOffchain() public pure {
        assertEq(AttestationLib.hashStruct(fixtureAttestation()), PINNED_HASH_STRUCT, "hashStruct diverged");
    }

    // ------------------------------------------------------------------
    // The domain
    // ------------------------------------------------------------------

    function test_DomainSeparatorFormulaMatchesOffchain() public pure {
        assertEq(
            domainSeparatorFor(FIXTURE_CHAIN_ID, FIXTURE_GUARD), PINNED_DOMAIN_SEPARATOR, "domain separator diverged"
        );
    }

    /// @dev And the guard really uses that formula, with its own address.
    function test_GuardUsesTheSameDomainFormula() public {
        vm.chainId(FIXTURE_CHAIN_ID);
        assertEq(guard.domainSeparator(), domainSeparatorFor(FIXTURE_CHAIN_ID, address(guard)));
    }

    // ------------------------------------------------------------------
    // The packed intent hash
    // ------------------------------------------------------------------

    function test_IntentHashMatchesOffchain() public view {
        bytes32 got = guard.computeIntentHash(
            FIXTURE_AGENT,
            FIXTURE_TARGET,
            0,
            abi.encodeWithSignature("ping()"),
            FIXTURE_POLICY,
            FIXTURE_CHAIN_ID,
            FIXTURE_VALID_UNTIL,
            0
        );
        assertEq(got, PINNED_INTENT_HASH, "computeIntentHash diverged from the signer");
    }

    // ------------------------------------------------------------------
    // End to end: a signature produced off-chain recovers here
    // ------------------------------------------------------------------

    /// @dev The assertion the whole bridge reduces to. If this passes, an
    ///      attestation signed by the Python evaluator is one this deployment
    ///      accepts.
    function test_OffchainSignatureRecoversToTheEvaluator() public pure {
        address recovered = ECDSA.recover(PINNED_DIGEST, PINNED_SIGNATURE);
        assertEq(recovered, 0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A, "off-chain signature does not recover");
    }

    /// @dev And the digest it signed is the one the guard would have computed,
    ///      for a guard deployed at the fixture address.
    function test_PinnedDigestIsTheGuardsDigest() public pure {
        bytes32 expected = keccak256(
            abi.encodePacked(
                hex"1901",
                domainSeparatorFor(FIXTURE_CHAIN_ID, FIXTURE_GUARD),
                AttestationLib.hashStruct(fixtureAttestation())
            )
        );
        assertEq(expected, PINNED_DIGEST, "the signed digest is not the one this contract verifies");
    }
}
