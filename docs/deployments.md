# ARF Onchain — Monad Testnet Deployment

✅ **These addresses match the current source.** Redeployed 2026-09-06 with all
Phase 1b fixes (off-chain signer binding, `anchorDecision`, derived agent ids,
`UNDETERMINED` reversibility). See [Deployment status](#deployment-status-2026-09-06)
below.

> ### ⚠️ Demonstration deployment — do not send funds
>
> These contracts are an **unaudited hackathon protocol with known, documented
> security flaws**. See [Known Limitations](../README.md#known-limitations) in
> the README before interacting with them.
>
> Do not deposit anything into `TreasuryVault`. Its `withdraw` is `onlyOwner`
> but checks the caller's own balance, so deposits from any other address are
> unrecoverable.
>
> Both the deployer and evaluator keys below are throwaway testnet-only keys
> generated for this deployment, held outside version control. Treat every
> address on this page as disposable.

**Network:** Monad Testnet
**Chain ID:** 10143 (`0x279f`)
**Deployer / owner:** `0x444F1f04451b4216854e1241228E999020b0D0d5`
**Trusted evaluator:** `0xb1C0e84Ed50d74eBd107624ec9B97334E242F36a`
**Addresses documented:** 2026-09-06
**On-chain state last verified:** 2026-09-11 (every field below re-read from
chain with `cast` — `chain-id`, `agentRegistry()`, `policyRegistry()`,
`trustedEvaluator()`, and the registered agent's `isActive` — all matched;
originally documented 2026-09-06, when it was also read back rather than
copied from deploy logs)

## Deployment status (2026-09-06)

**Redeployed and live.** Deployed with `forge script script/Deploy.s.sol
--broadcast`, using `forge` v1.8.1 installed via `foundryup`.

**A real bug was caught and fixed during this deployment, after the initial
broadcast.** `Deploy.s.sol` passed `msg.sender` as `ExecutionGuard`'s initial
trusted evaluator. Inside a Forge script's `run()`, `msg.sender` is Foundry's
script-default caller — `address(uint160(uint256(keccak256("foundry default
caller"))))`, a hash-derived constant with no discoverable private key — not
the address `vm.startBroadcast` uses to sign the transactions. The first
broadcast therefore deployed a guard whose `trustedEvaluator()` read back as
`0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38`: a real, checksummed address that
nobody can ever produce a valid signature for. `execute()` was permanently
unusable on that guard from the moment it was deployed.

This was caught by verifying `trustedEvaluator()` on-chain rather than trusting
the deploy log, and cross-checking the address against `forge-std/Base.sol`'s
`DEFAULT_SENDER` constant — which matched exactly. **The identical address is
recorded as the previous (2026-09-04) deployment's trusted evaluator in the
git history of this file**, with a note claiming it was set deliberately via
`setTrustedEvaluator`. That claim was never independently verified against
on-chain nonce/event data and was very likely the same unexamined bug, not a
deliberate rotation — the earlier deployment's guard was almost certainly also
unusable for the same reason. `Deploy.s.sol` now derives the deployer's address
with `vm.addr(deployerPrivateKey)` instead of reading `msg.sender`.

Fixed without a second full redeploy: the already-deployed guard's evaluator
was rotated with `setTrustedEvaluator` (owner-only, called from the deployer
key) to a freshly generated, controlled key
(`0xb1C0e84Ed50d74eBd107624ec9B97334E242F36a`). One agent was registered via
`script/RegisterAgent.s.sol` (the deployer's own wallet, matching the pattern
used in the prior deployment). Both actions are confirmed on-chain below, not
inferred from script output.

**Lesson for future deploys:** never trust a deploy script's own console
output as verification. Read the deployed state back independently — see
[Verifying this yourself](#verifying-this-yourself).

## Contracts

| Contract                  | Address                                      |
| ------------------------- | -------------------------------------------- |
| `AgentRegistry`           | `0x0398Aa2d8FC3A68525Ec787fF6c05fcE5395AFAd` |
| `PolicyRegistry`          | `0xa0b6dEDDbcceE56853032409f4990a1F9785a196` |
| `RiskAttestationRegistry` | `0x2698Db6946225149eD890f47e1996e03263F7B8D` |
| `ExecutionGuard`          | `0xCf783F76D33741fc0CA5339AF53D24a2b7f4c75d` |
| `TreasuryVault`           | `0x4aAa5e6D056b0F4245f32600Bd975280B58EEe39` |
| `AuditRegistry`           | `0x9c727eA41EE567918EFbF46007430FC84eBAc626` |

All six addresses were confirmed to hold contract code on Monad testnet on
2026-09-06 (`chain-id` 10143, block 60357494–60357523 for the deploy sequence).

## What `ExecutionGuard` is actually wired to

`ExecutionGuard` stores its three registry addresses as `immutable`, so they are
fixed at deployment and cannot be repointed. Read back from chain with `cast`:

| Field                     | Value                                        |
| ------------------------- | -------------------------------------------- |
| `agentRegistry()`         | `0x0398Aa2d8FC3A68525Ec787fF6c05fcE5395AFAd` |
| `policyRegistry()`        | `0xa0b6dEDDbcceE56853032409f4990a1F9785a196` |
| `attestationRegistry()`   | `0x2698Db6946225149eD890f47e1996e03263F7B8D` |
| `trustedEvaluator()`      | `0xb1C0e84Ed50d74eBd107624ec9B97334E242F36a` |
| `owner()` (AgentRegistry) | `0x444F1f04451b4216854e1241228E999020b0D0d5` |

`trustedEvaluator()` was rotated once, at block 60358675, from the buggy
default-caller value to the address above — see
[Deployment status](#deployment-status-2026-09-06).

## Registered agents

`ExecutionGuard` derives the agent key itself, as
`keccak256(abi.encodePacked(attestation.agent))` — it does not accept an agent
ID from the caller. For the deployer address that is:

```text
agentId = 0x9914a43c31eefd6e92dd784a3a04c090bb7fd7299732399de71713be27180410
```

Confirmed active with `cast call ... isActive(bytes32)` and confirmed to match
`agentIdFor(deployer)` on-chain — both the id derivation and the registration
were checked independently, not assumed from the register script's console
output.

## Verifying this yourself

Everything above is public chain state. To re-check it, with `cast`:

```bash
export RPC=https://testnet-rpc.monad.xyz
export GUARD=0xCf783F76D33741fc0CA5339AF53D24a2b7f4c75d
export AGENT_REGISTRY=0x0398Aa2d8FC3A68525Ec787fF6c05fcE5395AFAd

cast chain-id --rpc-url $RPC                      # expect 10143
cast code $GUARD --rpc-url $RPC | head -c 20      # expect non-empty

cast call $GUARD "agentRegistry()(address)"     --rpc-url $RPC
cast call $GUARD "trustedEvaluator()(address)"  --rpc-url $RPC

cast call $AGENT_REGISTRY \
  "isActive(bytes32)(bool)" \
  0x9914a43c31eefd6e92dd784a3a04c090bb7fd7299732399de71713be27180410 \
  --rpc-url $RPC
```

## Redeployment checklist

- [x] Deploy fresh registries and guard (the guard's registry pointers are immutable)
- [x] Call `RiskAttestationRegistry.setExecutionGuard` — without it every
      `recordAttestation` and every `anchorDecision` reverts
- [x] Call `setTrustedEvaluator` and record the value here — required this
      time because of the `msg.sender` bug documented above, not merely as a
      rotation from the deployer
- [x] Register agents with `script/RegisterAgent.s.sol` (the id is derived now)
- [x] Delete the orphaned `0x875f06…` reference from the scripts
- [x] Replace the address table above and note the superseded addresses
- [x] Remove the ABI-divergence banner at the top of this file
- [x] Re-pin the off-chain signer's `EIP712Domain.verifying_contract` to the new
      `ExecutionGuard` address — done in `enterprise/examples/fsx_governance_to_chain.py`;
      the library itself (`arf_enterprise.onchain.attestation.EIP712Domain`) takes
      the contract address as a parameter and has no address baked in

## Superseded deployment (2026-09-04)

The previous deployment (`AgentRegistry` at `0x7C17981030399d0b51b097a9483e60df8F3ce7A7`,
`ExecutionGuard` at `0x58B7fa769d95D0C88D7080BCA50533C660e7E74e`, and the rest of
that set) predates the Phase 1b fixes and, per the analysis above, was almost
certainly deployed with the same unusable-evaluator bug. It is superseded and
should not be used. Full detail on why it was already unusable before this
redeploy remains in git history of this file if needed.
