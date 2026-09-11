[![Monad Metropolis](https://img.shields.io/badge/Monad-Metropolis-6A5ACD?style=for-the-badge)](https://hackathon.monad.xyz/)
[![Track: Trust, Identity & AI Infrastructure](https://img.shields.io/badge/Track-Trust%2C%20Identity%20%26%20AI%20Infrastructure-00B4D8?style=for-the-badge)](<>)
[![Week 1 Complete](https://img.shields.io/badge/Week%201-Complete-2ECC40?style=for-the-badge)](<>)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![CI](https://github.com/arf-foundation/arf-onchain/actions/workflows/ci.yml/badge.svg)](https://github.com/arf-foundation/arf-onchain/actions/workflows/ci.yml)

# ARF Onchain

## Autonomous Agent Governance Infrastructure for Monad

> **AI proposes. ARF governs. Cryptography verifies. Monad executes.**

> ### ⚠️ Status: early hackathon protocol — unaudited, with known flaws
>
> This README describes the intended architecture. Much of it is not built yet,
> and part of what is built does not yet work as described.
>
> **Built:** six Solidity contracts, deployed to Monad testnet. Registration and
> deployment scripts. A 37-test suite covering `ExecutionGuard`, `AgentRegistry`
> and the adversarial cases.
>
> **Not built:** the reference decision engine, the governance API, the demo
> agent, the indexer, the frontend, the threat model, and a stateful invariant
> suite.
>
> **Fixed in source and redeployed (2026-09-06):** the evaluator signature now
> covers the whole attestation as EIP-712 typed data, including the decision
> field; `recordAttestation` is restricted to the guard; `registerAgent`
> derives the agent id; refusals are recorded on-chain by `anchorDecision`;
> and an `APPROVE` carrying an `UNDETERMINED` reversibility is rejected.
> Current addresses are in [`docs/deployments.md`](docs/deployments.md), which
> also documents a deploy-script bug caught and fixed during this redeploy —
> the initial trusted evaluator was accidentally set to an address no one
> holds a private key for. Read [Known Limitations](#known-limitations) for
> what is still open.
>
> Nothing here has been independently audited. Do not use this to secure funds.

ARF Onchain is a governance and execution-control layer for autonomous AI agents operating on-chain.

It sits between an agent's intent and blockchain execution, evaluating identity, policy, risk, exposure, and reversibility before an economically consequential action is allowed to execute.

```text
AI Agent
    │
    │ Transaction Intent
    ▼
┌──────────────────────────────┐
│          ARF ENGINE          │
│                              │
│  Identity                    │
│  Policy                      │
│  Risk                        │
│  Exposure                    │
│  Reversibility               │
│  Decision Governance         │
└──────────────┬───────────────┘
               │
               │ Signed Risk Attestation
               ▼
┌──────────────────────────────┐
│   RISK ATTESTATION REGISTRY  │
│                              │
│  Intent Hash                 │
│  Policy Hash                 │
│  Model Hash                  │
│  Risk Score                  │
│  Decision                    │
│  Reversibility               │
│  Expiration                  │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│       EXECUTION GUARD        │
│                              │
│  Identity verification       │
│  Attestation verification    │
│  Policy enforcement          │
│  Replay protection           │
│  Expiry validation           │
│  Exposure limits             │
└──────────────┬───────────────┘
               │
               ▼
        ┌──────────────┐
        │    MONAD     │
        │  Execution   │
        └──────────────┘
```

---

## The Problem

Autonomous AI agents can increasingly reason, plan, and initiate financial actions.

Blockchains make those actions immediately executable.

This creates a critical gap:

```text
AI Intent  ───────────────────────► Economic Execution
                 ?
          Governance Boundary
```

An agent may be capable of deciding what to do without being trusted to decide what it is allowed to do.

ARF Onchain provides that missing governance boundary.

The agent proposes an action.

ARF evaluates it.

Cryptography binds the governance decision to the exact transaction.

The execution layer enforces the decision.

Monad executes only what is authorized.

---

## Why This Needs A Chain, Not Just A Log

It would be easy to build the governance boundary above as an off-chain
service with a Postgres audit table, and reasonable to ask why Monad is in
this picture at all rather than being decorative.

The answer is in the reversibility example already described above: whether
`delete_volume` is recoverable is not a property of the verb, it is a reading
of live provider state at the moment of the request — final-backup or not,
readable or not. That reading is a claim, and a claim is worth nothing if the
party who made it can revise it after the fact. An off-chain log is exactly
that kind of revisable claim; a database row can be edited or deleted by
whoever holds the credentials, silently, with no trace that it happened.

Anchoring the signed attestation on Monad makes the reading permanent and
attributable instead: the operator, an auditor, and the agent all see the same
record, and none of them — including ARF itself — can edit it afterward.

The part worth proving is specifically the **refusals**. An approved action
that executes leaves an ordinary transaction receipt behind either way. A
denied or escalated one does not: it never runs, so there is nothing in a
normal execution log to show that ARF was ever asked, or what it decided.
`RiskAttestationRegistry.anchorDecision` exists to record exactly that
verdict — DENY, ESCALATE, or an `UNDETERMINED` reversibility included —
permissionlessly, in a transaction that succeeds precisely because it executes
nothing. That is the case an application database cannot make credibly and a
chain can: not "the system ran safely," but "the system was asked to do
something unsafe, and refused, and cannot quietly take that back."

This is runnable, not just argued — see
[Demo — Runnable Today](#demo--runnable-today).

---

## The Solution

ARF Onchain provides programmable governance for autonomous economic agents.

Every transaction intent is evaluated against:

- **Identity** — Is this agent authorized to act?
- **Policy** — Is the requested action permitted?
- **Risk** — How dangerous is the action?
- **Exposure** — Does it exceed the agent's financial limits?
- **Reversibility** — Can the action be reversed, compensated, or recovered?
- **Decision governance** — Should the action be approved, escalated, or denied?

The result is a cryptographically verifiable governance attestation.

```text
                 ┌─────────────┐
                 │   AI Agent  │
                 └──────┬──────┘
                        │
                  Intent / Action
                        │
                        ▼
                 ┌─────────────┐
                 │     ARF     │
                 │   Evaluate  │
                 └──────┬──────┘
                        │
              Signed Attestation
                        │
                        ▼
             ┌───────────────────┐
             │ Execution Guard   │
             └─────────┬─────────┘
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
       APPROVE      ESCALATE       DENY
          │            │
          │       Human approval
          │            │
          └────────────┘
               │
               ▼
             Monad
```

---

## Core Decision Model

ARF produces one of three governance outcomes.

| Decision   |          Risk | Action                  |
| ---------- | ------------: | ----------------------- |
| `APPROVE`  |      `< 0.20` | Autonomous execution    |
| `ESCALATE` | `0.20 – 0.75` | Human approval required |
| `DENY`     |      `≥ 0.75` | Execution blocked       |

Risk is evaluated together with policy, identity, exposure, and reversibility.

These boundaries are not arbitrary. They fall out of the ARF engine's expected-loss
minimization: with a false-approval cost of `10`, a false-denial cost of `8` and a
human-review cost of `2`, the escalate/deny boundary is
`1 − (review / false_denial) = 1 − 2/8 = 0.75`, and the approve/escalate boundary is
`review / false_approval = 2/10 = 0.20`.

### Reversibility

Every governed action is classified as:

```text
REVERSIBLE
COMPENSABLE
IRREVERSIBLE
UNDETERMINED
```

This allows ARF to distinguish between actions that can be safely recovered and actions that create permanent or difficult-to-recover exposure.

`UNDETERMINED` is not a fourth degree of recoverability. It is the absence of a
reading: the evaluator could not observe enough provider state to classify the
action. It is refused exactly as harshly as `IRREVERSIBLE` — `ExecutionGuard`
rejects any `APPROVE` carrying it — and recorded separately because "we could
not tell" and "we knew it was permanent" are different findings, and only one
of them indicates a broken evaluator.

Classification is deliberately a reading, not a lookup table. Whether deleting a
storage volume is recoverable depends on whether the request skips the final
backup, which is a property of the request and the live resource rather than of
the verb — so a governance layer that classified by action name would be wrong
on precisely the case that matters.

---

## Example

A treasury agent proposes three transfers:

| Transaction    |   Risk | Reversibility  | Decision    |
| -------------- | -----: | -------------- | ----------- |
| `$500 USDC`    | `0.04` | `REVERSIBLE`   | `APPROVED`  |
| `$7,500 USDC`  | `0.57` | `COMPENSABLE`  | `ESCALATED` |
| `$45,000 USDC` | `0.94` | `IRREVERSIBLE` | `DENIED`    |

The important property is that the agent is not allowed to bypass the governance layer.

```text
Safe action
    ↓
ARF approval
    ↓
Monad execution

Suspicious action
    ↓
ARF escalation
    ↓
Human approval
    ↓
Monad execution

Dangerous action
    ↓
ARF denial
    ↓
Execution blocked
```

---

# Architecture

## Components

### AgentRegistry

Registers autonomous agents and their authorization boundaries.

Stores information such as:

```text
Agent identity
Owner
Wallet
Status
Transaction limits
Exposure limits
```

### PolicyRegistry

Stores machine-enforceable governance policies.

Policies can constrain:

```text
Allowed assets
Allowed contracts
Transaction limits
Daily exposure
Required approvals
Agent permissions
```

### RiskAttestationRegistry

Stores and verifies ARF governance attestations.

The contract does not attempt to reproduce the full ARF risk model on-chain.

Instead, it verifies a cryptographically signed result containing:

```text
Intent hash
Policy hash
Model hash
Risk score
Decision
Reversibility
Evaluator
Timestamp
Expiration
```

This preserves a clean separation between probabilistic reasoning and on-chain enforcement.

### ExecutionGuard

The execution boundary.

It validates the governance attestation before allowing an agent to execute a transaction.

Conceptually:

```text
Valid identity
      +
Valid attestation
      +
Correct intent hash
      +
Valid policy
      +
Valid signature
      +
Not expired
      +
Not replayed
      +
Within limits
      +
APPROVE
      =
EXECUTE
```

Anything else is rejected.

### TreasuryVault

Provides an isolated execution environment for agent-controlled funds.

The agent does not receive unrestricted access to the treasury.

Its authority is constrained by ARF governance and vault policies.

### AuditRegistry

Records governance and execution events for verification and historical analysis.

---

# Cryptographic Trust Boundary

ARF Onchain intentionally separates **decision intelligence** from **execution enforcement**.

```text
OFF-CHAIN
─────────────────────────────────────

ARF Decision Engine

Bayesian risk analysis
Policy evaluation
Historical context
External intelligence
Reversibility analysis
Expected-loss reasoning

                │
                │ Signed Attestation
                ▼

ON-CHAIN
─────────────────────────────────────

RiskAttestationRegistry
        │
        ▼
ExecutionGuard
        │
        ▼
Monad
```

The blockchain does not need to reproduce every internal ARF calculation.

Instead, it independently verifies:

1. Who evaluated the action.
2. What exact action was evaluated.
3. Which policy and model were used.
4. What risk and governance decision were produced.
5. Whether the authorization is still valid.
6. Whether the authorization has already been consumed.

All six are verified in the current source: items 3 and 4 became real with the
EIP-712 change, which brings the model hash, risk score, reversibility and
decision under the evaluator's signature. The **deployed** contracts still
predate that change. See [Known Limitations](#known-limitations).

---

# Intent Binding

A governance decision must correspond to the exact transaction being executed.

The intent is cryptographically bound to transaction-specific data:

```text
Agent
Target
Value
Calldata
Nonce
Policy hash
Chain ID
Expiration
```

> `modelHash`, `riskScore`, `reversibility` and `decision` are not part of
> `intentHash` itself, but all four are covered by the evaluator's EIP-712
> signature over the whole `RiskAttestation` struct (see
> [`AttestationLib.sol`](contracts/AttestationLib.sol)), so the binding below
> holds for the governance _verdict_ as well as the transaction's shape.
> Confirmed live on the currently deployed `ExecutionGuard`: calling
> `hashAttestation()` with the same attestation but a different `decision`
> returns a different digest. See [Known Limitations](#known-limitations)
> item 1.

The resulting:

```text
intentHash
```

is included in the signed ARF attestation.

`ExecutionGuard` recomputes the hash before execution.

Therefore:

```text
Attestation for Transaction A
             ≠
Authorization for Transaction B
```

An attacker cannot simply capture a valid authorization and substitute a different recipient, amount, contract, or calldata.

---

# Security Properties — Target Invariants

> **Partially established.** Several of these are now covered by tests in
> [`test/attack_scenarios.t.sol`](test/attack_scenarios.t.sol) and
> [`test/ExecutionGuard.t.sol`](test/ExecutionGuard.t.sol) — including the three
> that were outright false before the EIP-712 fix. Exposure limits are still not
> enforced, and nothing here has been independently audited, so this remains a
> statement of intent backed by the author's own tests rather than a security
> guarantee. See [Known Limitations](#known-limitations).

The protocol is designed around the following invariants:

```text
APPROVE is required for autonomous execution.

An attestation cannot be replayed.

An attestation cannot authorize a different intent.

Expired attestations cannot execute.

Inactive agents cannot execute.

Unauthorized callers cannot execute.

Policy limits cannot be bypassed.

Invalid evaluator signatures are rejected.

DENY cannot be converted into execution.

ESCALATE cannot bypass human approval.
```

## Known Limitations

The following are known gaps between the design above and the current code.
They are listed here rather than in a separate document so that no reader
mistakes intent for implementation.

**A fix committed before a redeploy is live on the deployed contracts; a fix
committed after one is not, until the next redeploy.** The last redeploy was
2026-09-06 22:57 EDT (see [`docs/deployments.md`](docs/deployments.md)).
Items 1, 2, 4 and 5 below all landed before that timestamp and were verified
directly against the live contracts with `cast`, not assumed from source —
each says so. Item 7 landed 2026-09-08, after the redeploy, and is the one
gap that is genuinely still exploitable on the addresses in
`docs/deployments.md` today.

**1. ~~The evaluator signature does not cover the governance decision.~~ FIXED
in source and confirmed live on the deployed contracts.**

`ExecutionGuard` now verifies an EIP-712 signature over the entire
`RiskAttestation` struct, so `decision`, `riskScore`, `reversibility` and
`modelHash` are all bound. Mutating any field invalidates the signature; the
EIP-712 domain additionally binds an attestation to this chain and to a specific
guard deployment. The canonical encoding lives in
[`contracts/AttestationLib.sol`](contracts/AttestationLib.sol), and
`ExecutionGuard.hashAttestation()` exposes the digest so off-chain signers can
confirm they produce the same one.

Covered by `test_Regression_DenyCannotBeExecutedAsApprove`,
`test_Regression_EscalateCannotBeExecutedAsApprove`,
`test_Regression_RiskScoreCannotBeFabricated`,
`test_MutatingAnyAttestationFieldInvalidatesTheSignature` and
`test_SignatureDoesNotTransferToAnotherGuardDeployment`. Confirmed live:
`cast call`ing the deployed `ExecutionGuard.hashAttestation()` with the same
attestation and `decision` set to `APPROVE` vs. `DENY` returns two different
digests.

**2. ~~`RiskAttestationRegistry.recordAttestation` has no caller
restriction.~~ FIXED in source and confirmed live on the deployed contracts.**

Only the bound `ExecutionGuard` may consume an attestation or emit
`AttestationIssued`. The binding is set by the owner after deployment via
`setExecutionGuard`, because the guard's constructor needs the registry's
address; until it is set, execution fails closed.

Covered by `test_Regression_OnlyGuardCanRecordAttestations`,
`test_Regression_PreRecordingDoesNotBlockLegitimateExecution` and
`test_ExecutionFailsClosedIfRegistryHasNoGuard`. Confirmed live: calling the
deployed `RiskAttestationRegistry.recordAttestation` directly, from an address
that is not the guard, reverts with `"RiskAttestationRegistry: not the
guard"`.

**3. Exposure limits are not enforced.**

`ExecutionGuard` holds no balance, so native-value transfers cannot execute and
`value` is `0` in practice — which makes the `maxTransactionValue` check
vacuous for the ERC-20 flows the demo describes. `dailyLimit` is stored in
`AgentRegistry` and read by nothing.

**`dailyLimit` is advisory and unenforced.** Enforcing it needs per-agent spend
accounting, a rolling window, and a guard-to-registry write path with its own
access control; none of that exists. Treat the field as a declared intent
recorded against the agent, not as a control. It is documented rather than
deleted because the value is already set on live registrations, and silently
removing a limit an operator believes is in force would be worse than saying
plainly that it never was.

**4. ~~The agent id is supplied by the caller.~~ FIXED in source and confirmed
live on the deployed contracts.**

`AgentRegistry.registerAgent` derives the id as
`keccak256(abi.encodePacked(wallet))` — the form `ExecutionGuard.execute()`
computes — and returns it. Previously the id was a parameter, so an agent could
be registered under an id the guard would never look up: registration
succeeded, the agent appeared active, and every execution reverted with "agent
inactive". One such registration is still live on testnet, and a second deploy
script existed solely to compute the id by hand.

Covered by `test_RegistrationUsesTheIdTheGuardDerives`.

**5. ~~Refusals were not recorded on-chain at all.~~ FIXED in source and
confirmed live on the deployed contracts.**

`ExecutionGuard` emitted `ExecutionDenied` and `ExecutionEscalated` and then
reverted. A reverted transaction produces no logs, so neither event could ever
appear in a receipt — the contracts declared an audit trail for refusals and
kept none. The only on-chain record was `AttestationIssued`, emitted inside
successful executions, making the chain a log of what ran rather than of what
was decided.

`RiskAttestationRegistry.anchorDecision` now records any verdict — including
DENY, ESCALATE, and an `UNDETERMINED` reversibility — in a transaction that
succeeds precisely because it executes nothing. Anchoring is permissionless
(the evaluator's signature is the authorisation) and deliberately does not
consume the attestation, so a recorded denial does not block the approval that
follows remediation. The dead events have been removed.

Covered by `test/Anchoring.t.sol`. Confirmed live: calling the deployed
`RiskAttestationRegistry.anchorDecision` with a well-formed but unsigned
attestation reverts with `"RiskAttestationRegistry: untrusted evaluator"` —
proof the function exists and runs its real verification logic, not that it
falls through to an unrelated fallback. `arf-onchain`'s own
[`script/DemoStorageGovernance.s.sol`](script/DemoStorageGovernance.s.sol)
exercises this end to end against a fresh local stack — see
[Demo — Runnable Today](#demo--runnable-today).

**6. `TreasuryVault` is not wired into the execution path** and its `withdraw`
function checks the caller's own balance while being `onlyOwner`, so deposits
from any other address are unrecoverable.

**7. ~~A bare `bytes32(0)` policy hash silently bypassed the policy check.~~
FIXED in source — deployed contracts still affected.**

`ExecutionGuard.execute()` used to skip `PolicyRegistry.isPolicyActive` entirely
when `attestation.policyHash == bytes32(0)`. That made "nobody set a real
hash" and "this transaction is deliberately unpoliced" the same bit pattern
and the same behavior — the same coverage-vs-compliance conflation the
off-chain policy engine's `PolicyEvaluator.covers()` exists specifically to
prevent, reintroduced on-chain.

The check is now unconditional: every attestation must reference a
registered, active policy. "No policy applies" is `UNPOLICED_SPEC`
(`arf_enterprise.onchain.policy_spec`, private `enterprise` repo) — a real,
named, hashed policy an owner registers via `PolicyRegistry.setPolicy` like
any other, not an implicit default.

**This is source-only, and unlike items 1, 2, 4 and 5 above, it was not fixed
before the 2026-09-06 redeploy — it landed 2026-09-08, two days after.** The
deployed `ExecutionGuard` still contains the old
`if (attestation.policyHash != bytes32(0))` bypass, so a `bytes32(0)`
attestation against the live contract still skips the policy check exactly as
before. Confirmed live, not assumed: calling the deployed
`PolicyRegistry.setPolicy` with a `bytes32(0)` hash as the owner succeeds
rather than reverting with `"PolicyRegistry: zero hash is reserved"`. **This
is the one item in this list that is still a real, live exploit against the
addresses in [`docs/deployments.md`](docs/deployments.md).**

`PolicyRegistry.setPolicy` also now refuses to register `bytes32(0)` at all
(`require(policyHash != bytes32(0))`) in source, so once redeployed the
reservation will hold structurally rather than by convention — an owner
mistake or a registration script with an uncomputed-hash bug will not be able
to silently reactivate the old ambiguity by making zero an active policy.

Covered by `test_UnregisteredZeroPolicyHashNoLongerBypassesTheCheck`,
`test_ExplicitlyRegisteredUnpolicedSentinelAllowsExecution`, and
`PolicyRegistry.t.sol`'s `test_ZeroHashCanNeverBeRegistered`.

**8. Neither the contracts nor the fixes above have been independently
audited.** The test suite is written by the same people who wrote the
contracts, and passing tests are evidence about the cases someone thought to
write, not a security review.

---

# Repository Structure

```text
arf-onchain/
│
├── contracts/
│   ├── AgentRegistry.sol
│   ├── PolicyRegistry.sol
│   ├── AttestationLib.sol
│   ├── RiskAttestationRegistry.sol
│   ├── ExecutionGuard.sol
│   ├── TreasuryVault.sol
│   └── AuditRegistry.sol
│
├── script/
│   ├── Deploy.s.sol
│   ├── RegisterAgent.s.sol
│   ├── TestExecutionGuard.s.sol
│   └── DemoStorageGovernance.s.sol  # runnable — see Demo — Runnable Today
│
├── test/
│   ├── Harness.sol                  # shared setup, not a test suite itself
│   ├── AgentRegistry.t.sol
│   ├── PolicyRegistry.t.sol
│   ├── ExecutionGuard.t.sol
│   ├── Anchoring.t.sol
│   ├── OffchainSignature.t.sol
│   └── attack_scenarios.t.sol
│
├── docs/
│   └── deployments.md
│
├── .github/
│   └── workflows/
│       └── ci.yml
│
├── foundry.toml
└── CONTRIBUTING.md
```

That is the whole repository. The off-chain components described in the
architecture sections above — the reference decision engine, the governance
API, the demo agent, the Envio indexer and the frontend — are **planned, not
present**. So are the threat model and protocol documents. See the
[Roadmap](#roadmap) for what is actually built.

CI runs `forge fmt --check`, `forge build` and `forge test` on every push and
pull request — see [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

---

# Quick Start

## Prerequisites

Install:

- [Foundry](https://book.getfoundry.sh/)
- Node.js 20+
- Python 3.11+
- Git

A wallet with Monad Testnet MON is required for deployment and transactions.

## Clone

```bash
git clone https://github.com/arf-foundation/arf-onchain.git
cd arf-onchain
```

## Install Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Verify:

```bash
forge --version
```

---

# Build the Contracts

```bash
forge build
```

Expected result:

```text
Compiler run successful
```

---

# Run the Test Suite

```bash
forge test -vv
```

69 tests across six suites:

- `test/Harness.sol` — shared setup and EIP-712 signing helpers, not a suite
  itself.
- `test/ExecutionGuard.t.sol` (29 tests) — the checks in `execute()`:
  decisions, identity, caller authorization, evaluator trust and rotation,
  signature validity, EIP-712 field binding and domain separation, expiry,
  replay, intent binding, policy state, and registry binding.
- `test/Anchoring.t.sol` (13 tests) — `anchorDecision`: permissionless
  recording of every verdict including refusals, replay of an already-anchored
  digest, and the separation from `usedAttestations`.
- `test/AgentRegistry.t.sol` (8 tests) — registration, derived agent ids,
  activation state.
- `test/PolicyRegistry.t.sol` (7 tests) — policy registration, the zero-hash
  reservation, activation and deactivation.
- `test/OffchainSignature.t.sol` (7 tests) — the off-chain signer's encoding
  against `AttestationLib`'s, pinned so the two cannot drift silently.
- `test/attack_scenarios.t.sol` (5 tests) — the adversarial regressions for
  the historically fixed flaws.

Two tests document current behavior rather than assert desired behavior:
`test_PerTransactionLimitIsUnreachableForZeroValueCalls` and
`test_DailyLimitIsStoredButNeverEnforced`. They exist so
[Known Limitations](#known-limitations) item 3 is visible in the suite and not
only in prose.

A stateful invariant suite is still planned (see the [Roadmap](#roadmap)).
Passing tests are evidence about the cases someone thought to write; treat the
contracts as unreviewed until they are audited.

---

# Configure Monad

Create a local `.env` file:

```dotenv
MONAD_RPC_URL=
MONAD_CHAIN_ID=10143

DEPLOYER_PRIVATE_KEY=

ARF_EVALUATOR_PRIVATE_KEY=
```

Never commit `.env`.

The repository should only contain `.env.example`.

---

# Deploy to Monad Testnet

After configuring the environment:

```bash
source .env
```

Deploy:

```bash
forge script script/Deploy.s.sol \
  --rpc-url "$MONAD_RPC_URL" \
  --broadcast
```

For contract verification, configure the appropriate Monad verification settings before adding:

```bash
--verify
```

Record the deployed contract addresses in:

```text
docs/deployments.md
```

Example:

```text
Network: Monad Testnet
Chain ID: 10143

AgentRegistry:
0x...

PolicyRegistry:
0x...

RiskAttestationRegistry:
0x...

ExecutionGuard:
0x...

TreasuryVault:
0x...

AuditRegistry:
0x...
```

---

# Register an Agent

Configure the deployment addresses and environment variables, then:

```bash
forge script script/RegisterAgent.s.sol \
  --rpc-url "$MONAD_RPC_URL" \
  --broadcast
```

The registered agent receives an explicit execution boundary:

```text
Maximum transaction value
Daily exposure limit
Authorized owner
Approved assets
Approved contracts
Active/inactive status
```

---

# Off-Chain Components — Planned

The reference decision engine, the governance API and the demo treasury agent
described in the architecture sections above are **not in this repository yet.**
There is no `engine/`, `api/` or `agent/` package to install, and the commands
that previously appeared here (`pip install -e ./engine`, `uvicorn
arf_api.main:app`, `python -m treasury_agent.main`) did not correspond to
anything shipped.

What exists today is the on-chain layer: six contracts, two test files, the
deployment and registration scripts, and the Monad testnet deployment.

The intended off-chain shape is unchanged, and the agent loop it implements is:

```text
Observe
   ↓
Generate intent
   ↓
Submit to ARF
   ↓
Receive decision
   ↓
Approve / Escalate / Deny
   ↓
Execute only when authorized
```

See the [Roadmap](#roadmap) for sequencing. The production ARF decision engine
is proprietary and separate from anything planned here; see
[Public vs. Proprietary Components](#public-vs-proprietary-components).

---

# Demo — Runnable Today

[`script/DemoStorageGovernance.s.sol`](script/DemoStorageGovernance.s.sol) is
the runnable version of the [Why This Needs A Chain](#why-this-needs-a-chain-not-just-a-log)
argument above. No `.env`, no RPC, and no funded wallet:

```bash
forge script script/DemoStorageGovernance.s.sol -vvv
```

It deploys a fresh local stack, then requests `delete_volume` on the same
volume three times. Each request gets a different reversibility
classification and decision — `COMPENSABLE` / `ESCALATE`, `IRREVERSIBLE` /
`DENY`, `UNDETERMINED` / `DENY` — is signed as EIP-712 typed data the way
`ExecutionGuard` verifies it, and anchored with
`RiskAttestationRegistry.anchorDecision`, including the two refusals. The
script reads `isDecisionAnchored` back for each one rather than trusting its
own print statements.

The classification inputs (which case gets which reversibility) are
illustrative stand-ins, chosen to walk through all three bands — the
production reversibility engine that performs this classification against a
live cloud API is proprietary and outside this repository (see
[Public vs. Proprietary Components](#public-vs-proprietary-components)). What
is real: the contracts, the EIP-712 encoding, the signature, and the anchoring
transaction. This is the same shape the private production evaluator's
storage-governance integration emits, exercised here against public code
only.

---

# Demo — Planned Scenario

The canonical demo contains three transactions. **It is not yet runnable**: it
needs the off-chain evaluator that produces signed attestations, which is not in
this repository. The risk scores below are illustrative values chosen to land in
each decision band, not output from the ARF engine.

## 1. Safe

```text
Agent → $500 USDC

Risk: 0.04
Reversibility: REVERSIBLE
Decision: APPROVE
```

The transaction executes.

## 2. Suspicious

```text
Agent → $7,500 USDC

Risk: 0.57
Reversibility: COMPENSABLE
Decision: ESCALATE
```

A human must approve before execution.

## 3. Dangerous

```text
Agent → $45,000 USDC

Risk: 0.94
Reversibility: IRREVERSIBLE
Decision: DENY
```

`ExecutionGuard` blocks the transaction.

---

# Sponsor & Ecosystem Integrations

ARF Onchain is designed so ecosystem integrations reinforce the governance architecture rather than exist as isolated features.

Potential integrations include:

### Mera

Human/agent identity and passkey-based authorization.

```text
Human identity
      ↓
Agent ownership
      ↓
AgentRegistry
```

### Chainlink CRE

External data and workflow orchestration for risk and governance signals.

```text
External signals
       ↓
CRE workflow
       ↓
ARF evaluation
       ↓
Risk attestation
```

### Envio

Real-time indexing of governance and execution events.

```text
Monad events
      ↓
Envio
      ↓
Audit / Decision Explorer
```

### AI Model Layer

An AI model may generate transaction intents or plans.

The model does **not** receive unrestricted execution authority.

```text
AI
 ↓
Intent
 ↓
ARF
 ↓
Governance
 ↓
Execution
```

---

# What ARF Does Not Trust

ARF deliberately does not treat the following as sufficient authorization by themselves:

```text
LLM output
Agent confidence
Wallet ownership alone
Transaction profitability
Historical success alone
External API response alone
```

Authorization requires the complete governance path.

```text
Identity
+
Policy
+
Risk
+
Execution constraints
+
Cryptographic authorization
=
Governed execution
```

---

# Public vs. Proprietary Components

This repository is the public ARF Onchain integration and reference implementation.

The production ARF platform may contain proprietary components that are not included here, including advanced risk models, enterprise execution infrastructure, proprietary analytics, and other intellectual property.

The architectural boundary is:

```text
                 PUBLIC
                    │
                    ▼
      ┌──────────────────────────┐
      │      ARF Onchain         │
      │                          │
      │ Smart contracts          │
      │ Reference evaluator      │
      │ API interfaces           │
      │ Demo agent               │
      │ Frontend                 │
      │ Tests                    │
      └────────────┬─────────────┘
                   │
             Governance API
                   │
                   ▼
                PRIVATE
      ┌──────────────────────────┐
      │      ARF Enterprise      │
      │                          │
      │ Production risk engine   │
      │ Proprietary models       │
      │ Enterprise infrastructure│
      │ Advanced memory          │
      └──────────────────────────┘
```

The public implementation remains independently understandable and runnable without exposing proprietary ARF intellectual property.

---

# Design Principles

### 1. AI proposes, but does not authorize itself

AI models generate intentions.

ARF determines whether those intentions are executable.

### 2. Governance must be enforceable

A policy that exists only in an application prompt is not a security boundary.

Execution constraints must ultimately be enforced at the execution layer.

### 3. Decisions must be cryptographically bound

An approval for one transaction must never authorize another.

### 4. Risk is contextual

Transaction value alone does not determine risk.

Identity, policy, exposure, historical behavior, external intelligence, and recoverability can all affect the decision.

### 5. Fail closed

When authorization cannot be verified:

```text
Do not execute.
```

### 6. Auditability is part of governance

Every consequential decision should be reconstructable from its intent, policy, risk assessment, authorization, and execution record.

---

# Roadmap

## Phase 1 — Protocol Foundation

- [x] Repository structure
- [x] AgentRegistry
- [x] PolicyRegistry
- [x] RiskAttestationRegistry
- [x] ExecutionGuard
- [x] TreasuryVault — deployed, not yet wired into the execution path
- [x] AuditRegistry
- [x] Monad Testnet deployment

## Phase 1b — Correctness and Coverage

The contracts are written and deployed; they are not yet correct or tested.
This phase closes the gaps in [Known Limitations](#known-limitations) and must
land before the protocol is presented as a security artifact.

- [x] EIP-712 signing over the full attestation, so the decision is bound
- [x] Restrict `recordAttestation` to `ExecutionGuard`
- [x] Derive `agentId` in `registerAgent` rather than trusting the caller
- [x] Record refusals on-chain — `anchorDecision`, and the dead denial events removed
- [x] An off-chain signer that produces a digest this guard accepts, with the
      encoding pinned on both sides so the two cannot drift silently
- [x] Reject `APPROVE` carrying an `UNDETERMINED` reversibility
- [ ] Enforce `maxTransactionValue` for token flows — `dailyLimit` is documented
      as advisory and unenforced
- [x] `ExecutionGuard` test suite, including regressions for both flaws above
- [x] Attack-scenario tests — [ ] stateful invariant suite
- [x] CI: `forge fmt --check` + `forge build` + `forge test` on every push
- [x] Redeploy and republish addresses

## Phase 2 — Governance Engine

- [x] Reference risk evaluator — `arf_enterprise.onchain.evaluator.ReferenceRiskEvaluator`
      (in the private `enterprise` repo) composes an existing risk score +
      recommendation with an actuator's reversibility reading into a signed
      `RiskAttestation`; rationale text is persisted off-chain (Postgres via
      arf-api's `/api/v1/onchain/rationale`), keyed by the same hash that is
      anchored on-chain
- [ ] Policy evaluation — `arf_enterprise.onchain.policy_spec.PolicySpec`
      (private `enterprise` repo) gives a policy a canonical hash and builds
      the enforcing `Policy` tree from the same spec, so the two cannot
      drift apart. `UNPOLICED_SPEC` is the "explicitly no policy applies"
      sentinel, replacing the old meaning of a bare `bytes32(0)` — see the
      `ExecutionGuard` change below. Still missing: nothing yet selects
      *which* registered policy applies to a given intent, or folds
      violations into the attested decision — every caller still hashes and
      references only the unpoliced sentinel
- [x] Reversibility classification — on-chain enum; classification is off-chain
- [x] APPROVE / ESCALATE / DENY — enum and branch logic in `ExecutionGuard`
- [x] Signed attestations — EIP-712 over the full struct
- [x] Intent binding — every attestation field is now covered by the signature
- [x] Replay protection — guard-only consumption

## Phase 3 — Autonomous Agent

- [ ] Treasury-Agent-01
- [ ] Autonomous intent generation
- [ ] Governed transaction execution
- [ ] Escalation workflow

## Phase 4 — Observability

- [ ] Envio indexer
- [ ] Decision explorer
- [ ] Agent explorer
- [ ] Audit explorer
- [ ] Exposure monitoring

## Phase 5 — Ecosystem Integrations

- [ ] Mera
- [ ] Chainlink CRE
- [ ] AI model integration
- [ ] Additional ecosystem integrations where they strengthen the governance layer

---

# Security

**This is an unaudited hackathon protocol with known, documented security flaws.**

Do not use it to hold or move funds of any kind. The Monad testnet deployment
exists to demonstrate the architecture; it is not a safe reference
implementation, and the addresses in [`docs/deployments.md`](docs/deployments.md)
should be treated as a demo, not a target.

Read [Known Limitations](#known-limitations) before drawing any conclusion about
what this protocol enforces. In particular, `PolicyRegistry.setPolicy` on the
**currently deployed** contracts does not yet reject a `bytes32(0)` policy
hash, so `ExecutionGuard.execute()`'s old zero-hash policy bypass — fixed in
source, not yet redeployed — remains live against the addresses in
[`docs/deployments.md`](docs/deployments.md). See [Known Limitations](#known-limitations)
item 7, verified directly against chain, not assumed from source.

A threat model and a formal security policy are planned but not yet written.
Until then, report anything you find by opening an issue or contacting the
maintainers directly. Please give the maintainers an opportunity to investigate
before disclosing publicly.

---

# Hackathon

## Monad Metropolis

**Track:** Trust, Identity & AI Infrastructure

**Project:** ARF Onchain

**Thesis:**

> Autonomous agents need an execution-control layer that can enforce identity, policy, risk, and authorization before economic actions reach the blockchain.

## 🤝 Looking for Teammates

**ARF Onchain is looking for collaborators!**

I'm building this for the **Monad Metropolis Hackathon** and actively recruiting:

| Role                         | Skills                             | What You'll Do                                                  |
| ---------------------------- | ---------------------------------- | --------------------------------------------------------------- |
| **Backend/Systems Engineer** | Rust, Go, Python                   | Build the API layer, integrate with Monad, optimize performance |
| **AI/ML Engineer**           | Python, Bayesian inference, LLMs   | Enhance the reference risk engine, integrate with Qwen          |
| **Frontend Developer**       | React, Next.js, TypeScript         | Build the governance dashboard and decision explorer            |
| **DevRel/Community**         | Technical writing, Discord/Twitter | Help with docs, demos, and hackathon visibility                 |

**Why join ARF Onchain?**

- Work on a real governance infrastructure project that solves a critical problem in autonomous AI.
- Contracts written and deployed to Monad testnet, with an honest, documented list of what still needs fixing — see [Known Limitations](#known-limitations). There is real, well-scoped work here.
- Built on Monad – high-throughput, low-latency execution.
- Strong prize potential: $30K track prize + multiple bounties.

**Interested?** DM me on Discord (@petterjuan) or open an issue on GitHub.

---

# One-Line Architecture

```text
AI Agent
    ↓
ARF Governance
    ↓
Signed Attestation
    ↓
ExecutionGuard
    ↓
Monad
```

# One-Line Product

> **Governance infrastructure for autonomous economic agents.**

# One-Line Pitch

> **AI proposes. ARF governs. Cryptography verifies. Monad executes.**

---

# License

Copyright © 2026 ARF Foundation.

Licensed under the Apache License, Version 2.0.

See [`LICENSE`](LICENSE) for the full license text.
