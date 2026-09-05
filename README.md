[![Monad Metropolis](https://img.shields.io/badge/Monad-Metropolis-6A5ACD?style=for-the-badge)](https://hackathon.monad.xyz/)
[![Track: Trust, Identity & AI Infrastructure](https://img.shields.io/badge/Track-Trust%2C%20Identity%20%26%20AI%20Infrastructure-00B4D8?style=for-the-badge)](<>)
[![Week 1 Complete](https://img.shields.io/badge/Week%201-Complete-2ECC40?style=for-the-badge)](<>)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

# ARF Onchain

## Autonomous Agent Governance Infrastructure for Monad

> **AI proposes. ARF governs. Cryptography verifies. Monad executes.**

> ### ⚠️ Status: early hackathon protocol — unaudited, with known flaws
>
> This README describes the intended architecture. Much of it is not built yet,
> and part of what is built does not yet work as described.
>
> **Built:** six Solidity contracts, deployed to Monad testnet. Registration and
> deployment scripts. Partial tests for `AgentRegistry`.
>
> **Not built:** the reference decision engine, the governance API, the demo
> agent, the indexer, the frontend, the threat model, the attack/invariant test
> suites, and CI.
>
> **Known to be broken:** the evaluator signature does not cover the governance
> decision, so a caller can change `APPROVE`/`ESCALATE`/`DENY` on a validly
> signed attestation. Read [Known Limitations](#known-limitations) before
> treating anything below as an enforced guarantee.
>
> Do not use this to secure funds.

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
```

This allows ARF to distinguish between actions that can be safely recovered and actions that create permanent or difficult-to-recover exposure.

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

This is the intended design. **In the current implementation, items 3 and 4 are
not actually verified** — the model hash, risk score and decision are supplied by
the caller and are not covered by the evaluator's signature. See
[Known Limitations](#known-limitations).

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

> **Currently incomplete.** `modelHash`, `riskScore`, `reversibility` and — most
> importantly — `decision` are **not** part of `intentHash` and are not otherwise
> covered by the evaluator's signature. The binding below therefore holds for
> the transaction's _shape_ but not for the governance _verdict_ attached to it.
> See [Known Limitations](#known-limitations).

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

> **These are design goals, not verified properties.** They are the invariants
> the protocol is being built toward. They are **not** currently established by
> tests, and at least three of them do not hold in the current implementation
> (see [Known Limitations](#known-limitations) below). Do not cite this list as
> evidence of the protocol's security.

The protocol is being designed around the following intended invariants:

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

**1. The evaluator signature does not cover the governance decision.**

`ExecutionGuard` verifies a signature over `attestation.intentHash` alone, and
`intentHash` binds only `(agent, target, value, data, policyHash, chainId,
expiry, nonce)`. The `decision`, `riskScore`, `reversibility` and `modelHash`
fields arrive as unauthenticated calldata. A caller holding a signed
attestation can therefore submit it with a different `decision`. This means
the invariants _"DENY cannot be converted into execution"_, _"ESCALATE cannot
bypass human approval"_ and _"APPROVE is required for autonomous execution"_
**do not currently hold**. The fix is to sign the full attestation as EIP-712
typed data.

**2. `RiskAttestationRegistry.recordAttestation` has no caller restriction.**

Any address can mark an `intentHash` as consumed, permanently preventing a
legitimate execution, and any address can emit `AttestationIssued` events.
Replay protection and the on-chain audit trail are both writable by third
parties.

**3. Exposure limits are not enforced.**

`ExecutionGuard` holds no balance, so native-value transfers cannot execute and
`value` is `0` in practice — which makes the `maxTransactionValue` check
vacuous for the ERC-20 flows the demo describes. `dailyLimit` is stored in
`AgentRegistry` and read by nothing.

**4. `TreasuryVault` is not wired into the execution path** and its `withdraw`
function checks the caller's own balance while being `onlyOwner`, so deposits
from any other address are unrecoverable.

**5. `ExecutionGuard` has no meaningful test coverage.** See
[Run the Test Suite](#run-the-test-suite).

---

# Repository Structure

```text
arf-onchain/
│
├── contracts/
│   ├── AgentRegistry.sol
│   ├── PolicyRegistry.sol
│   ├── RiskAttestationRegistry.sol
│   ├── ExecutionGuard.sol
│   ├── TreasuryVault.sol
│   └── AuditRegistry.sol
│
├── script/
│   ├── Deploy.s.sol
│   ├── RegisterAgent.s.sol          # superseded — see RegisterAgentCorrect
│   ├── RegisterAgentCorrect.s.sol
│   └── TestExecutionGuard.s.sol
│
├── test/
│   ├── AgentRegistry.t.sol
│   └── ExecutionGuard.t.sol         # placeholder — see Run the Test Suite
│
├── docs/
│   └── deployments.md
│
├── foundry.toml
└── CONTRIBUTING.md
```

That is the whole repository. The off-chain components described in the
architecture sections above — the reference decision engine, the governance
API, the demo agent, the Envio indexer and the frontend — are **planned, not
present**. So are the threat model and protocol documents. See the
[Roadmap](#roadmap) for what is actually built.

There is no CI configuration in this repository; nothing is checked
automatically on push.

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

**Current coverage is minimal, and the security boundary is untested.**
`AgentRegistry.t.sol` covers registration, deactivation and nonce handling.
`ExecutionGuard.t.sol` is a placeholder: its single test asserts only that the
contract deployed to a non-zero address. There is no test that exercises
`execute()`, and therefore no test behind any of the
[target invariants](#security-properties--target-invariants).

An attack/invariant suite is planned (see the [Roadmap](#roadmap)); it does not
exist yet. Treat the contracts as unreviewed.

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

- [ ] EIP-712 signing over the full attestation, so the decision is bound
- [ ] Restrict `recordAttestation` to `ExecutionGuard`
- [ ] Derive `agentId` in `registerAgent` rather than trusting the caller
- [ ] Enforce (or remove) `maxTransactionValue` and `dailyLimit` for token flows
- [ ] `ExecutionGuard` test suite, including regressions for the two flaws above
- [ ] Attack-scenario and invariant test suites
- [ ] CI: `forge build` + `forge test` on every push
- [ ] Redeploy and republish addresses

## Phase 2 — Governance Engine

- [ ] Reference risk evaluator
- [ ] Policy evaluation
- [x] Reversibility classification — on-chain enum; classification is off-chain
- [x] APPROVE / ESCALATE / DENY — enum and branch logic in `ExecutionGuard`
- [ ] Signed attestations — signature does not yet cover the decision
- [ ] Intent binding — partial; `modelHash` and `decision` are unbound
- [x] Replay protection — present, but the registry write is unrestricted

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
what this protocol enforces. In particular, the evaluator signature does not
currently bind the governance decision, so the execution boundary can be
bypassed by the caller.

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
