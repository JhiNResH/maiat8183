# ERC-8183 Hook Contracts

**ERC-8183** — job escrow with evaluator attestation for trustless agent-to-agent commerce.

> **175 tests passing** · 5,310 lines of Solidity · [Audit report](./AUDIT-PR6.md)

## Specification

- **[hook-profiles.md](./hook-profiles.md)** — Recommended hook profiles: A (Simple Policy), B (Advanced Escrow), C (Experimental).

## Hook Extension Contracts

| Contract | Description |
|----------|-------------|
| **[AgenticCommerceHooked.sol](./contracts/AgenticCommerceHooked.sol)** | Hookable variant of the core protocol. Same lifecycle with an optional `hook` address per job and `optParams` on all hookable functions. `claimRefund` is deliberately not hookable. |
| **[IACPHook.sol](./contracts/IACPHook.sol)** | Interface all hooks must implement: `beforeAction` and `afterAction`. |
| **[BaseACPHook.sol](./contracts/BaseACPHook.sol)** | Abstract base that routes `beforeAction`/`afterAction` to named virtual functions (`_preFund`, `_postComplete`, etc.). Inherit this and override only what you need. |

## Hook Examples

| Contract | Profile | Description |
|----------|---------|-------------|
| [BiddingHook.sol](./contracts/hooks/BiddingHook.sol) | A — Simple Policy | Off-chain signed bidding for provider selection. Providers sign bid commitments; the hook verifies the winning signature on-chain via `setProvider`. Zero direct external calls — everything flows through core → hook callbacks. |
| [FundTransferHook.sol](./contracts/hooks/FundTransferHook.sol) | B — Advanced Escrow | Two-phase fund transfer for token conversion/bridging jobs. Client capital flows to provider at `fund`; provider deposits output tokens at `submit`; buyer receives them at `complete`. |

## Trust Extension Contracts

Contributed by [Maiat Protocol](https://github.com/JhiNResH/maiat-protocol) — trust infrastructure for agent commerce.

### Core Trust System

| Contract | Description |
|----------|-------------|
| **[EvaluatorRegistry.sol](./contracts/EvaluatorRegistry.sol)** | Trust-ranked evaluator discovery. Multiple evaluators per domain with on-chain performance tracking (success rate, total jobs). Paginated queries sorted by performance. Auto-delists underperforming evaluators. |
| **[TrustGateACPHook.sol](./contracts/hooks/TrustGateACPHook.sol)** | Gates job lifecycle by trust score from an external oracle. Dynamic value-tier thresholds — higher value jobs require higher trust. |
| **[TrustBasedEvaluator.sol](./contracts/hooks/TrustBasedEvaluator.sol)** | Reference evaluator that auto-approves/rejects based on provider trust score. Feeds outcomes back to EvaluatorRegistry for performance tracking. |

### Plugin Hooks

| Contract | Description |
|----------|-------------|
| **[AttestationHook.sol](./contracts/hooks/AttestationHook.sol)** | Records job outcomes as EAS attestations — permanent on-chain receipts for every completed or rejected job. Schema: jobId, client, provider, evaluator, budget, reason, completed. |
| **[TokenSafetyHook.sol](./contracts/hooks/TokenSafetyHook.sol)** | Checks payment token safety before `fund()` via an external oracle (honeypot, high tax, unverified). Blocks unsafe tokens from entering escrow. |
| **[MaiatRouterHook.sol](./contracts/hooks/MaiatRouterHook.sol)** | Composite hook router — chains multiple plugin hooks into one address. Supports ordered execution, per-plugin enable/disable, and emergency circuit breaker. Required because ERC-8183 only allows one hook per job. |

### Interfaces

| Interface | Description |
|-----------|-------------|
| **[ITrustOracle.sol](./contracts/interfaces/ITrustOracle.sol)** | Standard interface for trust score queries (`getTrustScore(address) → uint256`). |
| **[ITokenSafetyOracle.sol](./contracts/interfaces/ITokenSafetyOracle.sol)** | Standard interface for token safety checks (`isTokenSafe(address) → bool`). |

**Documentation:**
- [04-evaluator-patterns.md](./04-evaluator-patterns.md) — Four evaluator design patterns including trust-ranked discovery
- [05-attestation-patterns.md](./05-attestation-patterns.md) — EAS attestation integration patterns

### Architecture

```
MaiatRouterHook (composite router — one hook address per job)
  ├── TrustGateACPHook      →  Pre-screens participants by trust score
  ├── TokenSafetyHook       →  Blocks unsafe payment tokens
  └── AttestationHook       →  Records outcomes as EAS attestations

EvaluatorRegistry           →  Trust-ranked evaluator discovery
TrustBasedEvaluator         →  Auto-evaluates based on trust score
Registry.recordOutcome()    →  Feeds back performance data
```

## Building a Hook

1. Inherit `BaseACPHook` and override only the callbacks you need.
2. See [CONTRIBUTING.md](./CONTRIBUTING.md) for full guidelines.

## Contributing

Contributions, feedback, and discussion are welcome - please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to get started.

## License

MIT
