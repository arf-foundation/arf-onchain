# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

ARF Onchain is a Solidity governance/execution-control layer for autonomous AI
agents on Monad testnet: it separates off-chain risk decisioning (planned, not
built) from on-chain enforcement (built). The off-chain decision engine,
governance API, demo agent, indexer, and frontend described in `README.md` do
**not exist in this repo** — only the six contracts, tests, and deploy/register
scripts do. Don't assume packages like `engine/`, `api/`, or `agent/` exist.

This is an unaudited hackathon protocol with documented, intentionally-tracked
security flaws. Read the **Known Limitations** section of `README.md` before
changing `ExecutionGuard.sol`, `RiskAttestationRegistry.sol`, or
`AgentRegistry.sol` — several past bugs (unsigned decision field, unrestricted
`recordAttestation`, caller-supplied agent id, unrecorded refusals, zero-hash
policy bypass) were fixed in source but remain live in the deployed testnet
contracts, and the README explicitly tracks which is which. When fixing a
similar class of bug, update that section rather than leaving the deployed/
source discrepancy undocumented.

## Commands

Build:
```bash
forge build
```

Run the full test suite:
```bash
forge test -vv
```

Run a single test file:
```bash
forge test --match-path test/ExecutionGuard.t.sol -vvv
```

Run a single test by name:
```bash
forge test --match-test test_Regression_DenyCannotBeExecutedAsApprove -vvvv
```

Format check (CI enforces this):
```bash
forge fmt --check
forge fmt          # to fix
```

Coverage (reported in CI, not gated):
```bash
forge coverage --report summary
```

Deploy to Monad testnet (requires `.env` with `MONAD_RPC_URL`,
`DEPLOYER_PRIVATE_KEY`, `ARF_EVALUATOR_PRIVATE_KEY` — never commit `.env`):
```bash
source .env
forge script script/Deploy.s.sol --rpc-url "$MONAD_RPC_URL" --broadcast
```

Register an agent (after deployment):
```bash
forge script script/RegisterAgent.s.sol --rpc-url "$MONAD_RPC_URL" --broadcast
```

CI (`.github/workflows/ci.yml`) runs, in order: `forge fmt --check`,
`forge build --sizes`, `forge test -vvv`, then `forge coverage --report
summary` (non-blocking). It checks out submodules with `fetch-depth: 0` —
required because the pinned `openzeppelin-contracts` tag isn't reachable at
depth 1.

## Architecture

Six contracts in `contracts/`, forming a pipeline from agent identity through
signed off-chain risk decisions to enforced on-chain execution:

- **`AgentRegistry.sol`** — registers agents and their authorization
  boundaries (owner, wallet, status, tx/exposure limits). Agent id is
  *derived* on-chain as `keccak256(abi.encodePacked(wallet))`, not supplied by
  the caller — this must match what `ExecutionGuard.execute()` computes when
  looking up an agent, or execution reverts with "agent inactive" even for a
  successfully registered agent (this happened once; a stale bad registration
  is still live on testnet).
- **`PolicyRegistry.sol`** — stores machine-enforceable policy hashes and
  their active/inactive state. `bytes32(0)` can never be registered
  (`setPolicy` reverts on it), so it's permanently reserved as "unset," never
  reusable as an implicit "no policy" bypass.
- **`AttestationLib.sol`** — the canonical EIP-712 encoding for a
  `RiskAttestation` (intent hash, policy hash, model hash, risk score,
  decision, reversibility, evaluator, timestamp, expiration). This is the
  single source of truth for what the evaluator's signature covers; both the
  off-chain signer and `ExecutionGuard.hashAttestation()` must produce the
  same digest from it.
- **`RiskAttestationRegistry.sol`** — verifies and stores signed governance
  attestations produced off-chain. Deliberately does not reproduce ARF's risk
  model on-chain — it only checks the signature and records the verdict.
  `recordAttestation` may only be called by the bound `ExecutionGuard` (set
  post-deploy via `setExecutionGuard`, since the guard's constructor needs the
  registry's address — until set, execution fails closed). `anchorDecision`
  separately records *any* verdict, including DENY/ESCALATE, in a
  transaction that succeeds by executing nothing, so refusals are auditable on
  their own even though a reverted `execute()` produces no logs.
- **`ExecutionGuard.sol`** — the execution boundary. `execute()` requires,
  together: valid identity, valid attestation signature (over the whole
  EIP-712 struct, chain- and guard-bound), correct intent hash, an active
  registered policy (the policy check is unconditional — no zero-hash
  bypass), not expired, not replayed, and decision == APPROVE (an APPROVE
  with `UNDETERMINED` reversibility is rejected). Anything else reverts.
- **`TreasuryVault.sol`** — isolated fund custody for agents. **Not wired
  into the execution path**, and its `withdraw` is `onlyOwner` but checks the
  *caller's own* balance — deposits from any other address are currently
  unrecoverable. Do not treat it as production-ready.
- **`AuditRegistry.sol`** — records governance/execution events for
  historical analysis.

Trust boundary: off-chain (not in this repo) does the actual risk reasoning
and signs a `RiskAttestation`; on-chain only verifies signature validity,
field bindings, freshness, and policy state — it never recomputes risk.

### Tests (`test/`)

- `Harness.sol` — shared setup and EIP-712 signing helpers used by other test
  files; not a test file itself.
- `ExecutionGuard.t.sol` — the core `execute()` checks: decisions, identity,
  caller authorization, evaluator trust/rotation, signature validity, EIP-712
  field binding and domain separation, expiry, replay, intent binding, policy
  state, registry binding.
- `attack_scenarios.t.sol` — adversarial regressions for the historically
  fixed flaws (see Known Limitations in README).
- `AgentRegistry.t.sol`, `PolicyRegistry.t.sol`, `Anchoring.t.sol`,
  `OffchainSignature.t.sol` — per-contract behavior.

Two tests intentionally document current (not desired) behavior:
`test_PerTransactionLimitIsUnreachableForZeroValueCalls` and
`test_DailyLimitIsStoredButNeverEnforced` — exposure-limit enforcement is a
known gap, not a bug to silently fix without updating the README.

### Deployments

`docs/deployments.md` records live Monad testnet addresses and must be
updated after any redeploy, along with an explicit note on which
source-vs-deployed discrepancies (see Known Limitations) still apply to the
new deployment. Never deposit real funds into any deployed instance —
demonstration only.

## Solidity/Foundry conventions

- `solc` version is pinned to `0.8.25` in `foundry.toml`; `via_ir` is
  explicitly `false` (note: Foundry reads `via_ir`, not `via-ir` — the hyphen
  form is silently ignored).
- Remappings: `@openzeppelin/=lib/openzeppelin-contracts/`,
  `forge-std/=lib/forge-std/`. Both are git submodules pinned via
  `foundry.lock`, not npm/forge-installed deps — update via git submodule
  pointer + `foundry.lock`, not `forge install`.
- `ffi = true` is enabled in `foundry.toml`.
