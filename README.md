# ARF Onchain

## Autonomous Agent Governance Infrastructure for Monad

> **AI proposes. ARF governs. Cryptography verifies. Monad executes.**

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
| `ESCALATE` | `0.20 – 0.80` | Human approval required |
| `DENY`     |      `> 0.80` | Execution blocked       |

Risk is evaluated together with policy, identity, exposure, and reversibility.

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

This makes the execution boundary independently verifiable.

---

# Intent Binding

A governance decision must correspond to the exact transaction being executed.

The intent is cryptographically bound to transaction-specific data such as:

```text
Agent
Target
Value
Calldata
Nonce
Policy hash
Model hash
Chain ID
Expiration
```

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

# Security Properties

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

See [`SECURITY.md`](SECURITY.md) and the invariant/attack tests under [`test/`](test/).

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
│   ├── RegisterAgent.s.sol
│   └── DemoScenario.s.sol
│
├── test/
│   ├── AgentRegistry.t.sol
│   ├── PolicyRegistry.t.sol
│   ├── RiskAttestationRegistry.t.sol
│   ├── ExecutionGuard.t.sol
│   ├── TreasuryVault.t.sol
│   ├── AuditRegistry.t.sol
│   ├── attack_scenarios.t.sol
│   └── invariant.t.sol
│
├── engine/
│   └── src/
│       └── arf_reference/
│
├── api/
│   └── src/
│       └── arf_api/
│
├── agent/
│   └── src/
│       └── treasury_agent/
│
├── indexer/
│   └── envio/
│
├── frontend/
│
├── docs/
│   ├── threat-model.md
│   ├── protocol.md
│   ├── decisions.md
│   ├── identity.md
│   ├── risk-attestation.md
│   └── demo.md
│
└── .github/
    └── workflows/
```

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

Run the security/invariant suite:

```bash
forge test --match-path test/attack_scenarios.t.sol -vv
forge test --match-path test/invariant.t.sol -vv
```

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

# Run the Reference Decision Engine

The public repository contains a lightweight reference implementation of the governance interface.

Create the Python environment:

```bash
python -m venv .venv
source .venv/bin/activate
```

Install:

```bash
pip install -e ./engine
```

Run tests:

```bash
pytest engine/tests -v
```

The reference implementation is intentionally separated from ARF's proprietary production engine.

---

# Run the API

Install API dependencies:

```bash
pip install -e ./api
```

Start the service:

```bash
uvicorn arf_api.main:app --reload
```

The API accepts agent intents and returns governance decisions/attestations through the same conceptual interface used by the production ARF architecture.

---

# Run the Autonomous Agent

Install the agent package:

```bash
pip install -e ./agent
```

Run:

```bash
python -m treasury_agent.main
```

The demo agent follows:

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

---

# Demo

The canonical demo contains three transactions.

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
- [ ] AgentRegistry
- [ ] PolicyRegistry
- [ ] RiskAttestationRegistry
- [ ] ExecutionGuard
- [ ] TreasuryVault
- [ ] AuditRegistry
- [ ] Monad Testnet deployment

## Phase 2 — Governance Engine

- [ ] Reference risk evaluator
- [ ] Policy evaluation
- [ ] Reversibility classification
- [ ] APPROVE / ESCALATE / DENY
- [ ] Signed attestations
- [ ] Intent binding
- [ ] Replay protection

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

This project is being developed as a hackathon protocol and should be treated accordingly.

Do not use the current implementation to secure production funds without an independent security review.

See:

- [`SECURITY.md`](SECURITY.md)
- [`docs/threat-model.md`](docs/threat-model.md)
- [`test/attack_scenarios.t.sol`](test/attack_scenarios.t.sol)
- [`test/invariant.t.sol`](test/invariant.t.sol)

Security reports should not be disclosed publicly before the maintainers have had an opportunity to investigate.

---

# Hackathon

## Monad Metropolis

**Track:** Trust, Identity & AI Infrastructure

**Project:** ARF Onchain

**Thesis:**

> Autonomous agents need an execution-control layer that can enforce identity, policy, risk, and authorization before economic actions reach the blockchain.

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
