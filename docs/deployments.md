# ARF Onchain — Monad Testnet Deployment

> ### ⛔ These addresses no longer match the source in this repository
>
> The deployed contracts predate the current `contracts/`, and the interface
> has since changed. Do not generate calls from the source in this repo against
> the addresses below — they will revert in ways that look like bugs in your
> client and are not. Specifically:
>
> - `AgentRegistry.registerAgent` took `(bytes32 agentId, address wallet,
address owner, uint256, uint256)`; it now takes
>   `(address wallet, address owner, uint256, uint256)` and derives the id.
> - `RiskAttestationRegistry.Reversibility` gained a fourth member,
>   `UNDETERMINED`. Attestations encoding it cannot be represented by the
>   deployed enum.
> - `RiskAttestationRegistry.anchorDecision` does not exist on-chain yet, so
>   **no denial or escalation in the deployed system leaves any record at all.**
> - `ExecutionGuard.ExecutionDenied` and `ExecutionEscalated` were removed as
>   dead code; they are declared in the deployed bytecode but were never
>   observable, because both paths revert and a reverted transaction emits no
>   logs.
>
> A redeploy is required and needs a funded testnet wallet. Until then, treat
> everything below as a record of what is live, not as an integration target.

> ### ⚠️ Demonstration deployment — do not send funds
>
> These contracts are an **unaudited hackathon protocol with known, documented
> security flaws**. See [Known Limitations](../README.md#known-limitations) in
> the README before interacting with them.
>
> Most importantly: the evaluator signature does not cover the governance
> decision, so a caller holding a validly signed attestation can change
> `APPROVE` / `ESCALATE` / `DENY` on it. The execution boundary these addresses
> implement **can be bypassed by the caller**. They exist to demonstrate the
> architecture, not to enforce it.
>
> Do not deposit anything into `TreasuryVault`. Its `withdraw` is `onlyOwner`
> but checks the caller's own balance, so deposits from any other address are
> unrecoverable.
>
> These addresses will be replaced once the Phase 1b fixes land. Treat them as
> disposable.

**Network:** Monad Testnet
**Chain ID:** 10143 (`0x279f`)
**Current deployed owner:** `0xaa160C367632CAbcF46d6F7e423b56c71C8B4841`
**Addresses documented:** 2026-09-04
**On-chain state last verified:** 2026-09-04

## Deployment status (2026-09-06)

**Pending redeploy.** The fixes in this repository are ready to deploy. A new
deployer (`0x444F1f04451b4216854e1241228E999020b0D0d5`) has been generated for
testnet. Deployment awaits funding the new deployer address with testnet MON,
then running `forge script script/Deploy.s.sol --broadcast`.

## Contracts

| Contract                  | Address                                      |
| ------------------------- | -------------------------------------------- |
| `AgentRegistry`           | `0x7C17981030399d0b51b097a9483e60df8F3ce7A7` |
| `PolicyRegistry`          | `0xA56fbA988f78c2410f659cfd4fBA1B0abB0a35bd` |
| `RiskAttestationRegistry` | `0x3bA57C50B44717770bd1F5eA67C9D5Ad50E5819F` |
| `ExecutionGuard`          | `0x58B7fa769d95D0C88D7080BCA50533C660e7E74e` |
| `TreasuryVault`           | `0xa4b432faB9000833f41F2991BbC0E59727FBc3b9` |
| `AuditRegistry`           | `0xb4cB353Eb5f0F5C52E718a1c62592639fB0E3434` |

All six addresses were confirmed to hold contract code on Monad testnet on
2026-09-04.

## What `ExecutionGuard` is actually wired to

`ExecutionGuard` stores its three registry addresses as `immutable`, so they are
fixed at deployment and cannot be repointed. Read back from chain:

| Field                   | Value                                        |
| ----------------------- | -------------------------------------------- |
| `agentRegistry()`       | `0x7C17981030399d0b51b097a9483e60df8F3ce7A7` |
| `policyRegistry()`      | `0xA56fbA988f78c2410f659cfd4fBA1B0abB0a35bd` |
| `attestationRegistry()` | `0x3bA57C50B44717770bd1F5eA67C9D5Ad50E5819F` |
| `trustedEvaluator()`    | `0x1804c8Ab1F12E6BbF3894d4083F33e07309D1f38` |
| `owner()`               | `0xaa160C367632CAbcF46d6F7e423b56c71C8B4841` |

The trusted evaluator is **not** the deployer. `Deploy.s.sol` passes the
deployer as the initial evaluator; the live value was set afterwards via
`setTrustedEvaluator`. Only signatures from `0x1804c8Ab…` are accepted.

## Registered agents

`ExecutionGuard` derives the agent key itself, as
`keccak256(abi.encodePacked(attestation.agent))` — it does not accept an agent
ID from the caller. For the deployer address that is:

```text
agentId = 0x235e44f30ff9e9d302605f47dbaa2cfb5614b51773846d9ccecba70aa5a72ca4
```

That ID is registered and active in `0x7C1798…`, so the guard can resolve it.

A second entry, `keccak256("treasury-agent-01")` =
`0x43524ead…`, is also registered and active. It is a leftover from the first
run of `RegisterAgent.s.sol` and is **unreachable** — no address hashes to it,
so no `execute()` call can ever select it. It is inert, not dangerous, and it
illustrates the underlying contract issue: the deployed
`AgentRegistry.registerAgent` accepts an arbitrary `bytes32` agent ID with no
constraint tying it to the wallet, so it will happily store registrations the
guard can never use.

**Fixed in source.** `registerAgent` now derives the id from the wallet and
returns it, so the unreachable registration is no longer expressible. The
deployed contract still behaves as described above.

## Orphaned registry

An `AgentRegistry` at `0x875f065F8D50bc657F3f9fa37cdB44Df3990EC88` holds
contract code and contains a correctly-derived agent ID, but the deployed
`ExecutionGuard` does not read it — `agentRegistry()` is immutable and points at
`0x7C1798…`. Registering an agent there has no effect on anything the guard can
see.

It was targeted by `script/RegisterAgentCorrect.s.sol`, which existed only
because the id derivation had to be done by hand. That script has been deleted
and `script/RegisterAgent.s.sol` now reads its registry address from
`AGENT_REGISTRY_ADDRESS` rather than hardcoding one — a stale literal is how the
two scripts came to configure two different deployments in the first place.

The address in the table above is the live one.

## Verifying this yourself

Everything above is public chain state. To re-check it, with `cast`:

```bash
export RPC=https://testnet-rpc.monad.xyz
export GUARD=0x58B7fa769d95D0C88D7080BCA50533C660e7E74e

cast chain-id --rpc-url $RPC                      # expect 10143
cast code $GUARD --rpc-url $RPC | head -c 20      # expect non-empty

cast call $GUARD "agentRegistry()(address)"     --rpc-url $RPC
cast call $GUARD "trustedEvaluator()(address)"  --rpc-url $RPC

cast call 0x7C17981030399d0b51b097a9483e60df8F3ce7A7 \
  "isActive(bytes32)(bool)" \
  $(cast keccak $(cast abi-encode-packed "f(address)" 0xaa160C367632CAbcF46d6F7e423b56c71C8B4841)) \
  --rpc-url $RPC
```

## Redeployment checklist

When the Phase 1b fixes land, redeploy rather than patching around these
addresses, and update this file in the same commit:

- [ ] Deploy fresh registries and guard (the guard's registry pointers are immutable)
- [ ] Call `RiskAttestationRegistry.setExecutionGuard` — without it every
      `recordAttestation` and every `anchorDecision` reverts
- [ ] Call `setTrustedEvaluator` and record the value here
- [ ] Register agents with `script/RegisterAgent.s.sol` (the id is derived now)
- [x] Delete the orphaned `0x875f06…` reference from the scripts
- [ ] Replace the address table above and note the superseded addresses
- [ ] Remove the ABI-divergence banner at the top of this file
- [ ] Re-pin the off-chain signer's `EIP712Domain.verifying_contract` to the new
      `ExecutionGuard` address — the domain separator binds to it, so every
      attestation signed against the old address is rejected by the new guard
