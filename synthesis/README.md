# Synthesis Hackathon Simulation

This simulation demonstrates how Maiat8183 hooks would manage trust for AI agent judges in the [Synthesis hackathon](https://synthesis.md) — the first major event judged by AI agents.

## Context

- **569 projects** submitted to Synthesis (clients requesting evaluation)
- **AI judge agents** with zero reputation evaluate projects (providers)
- **Maiat8183** acts as the trust layer (evaluator of evaluators)

All 35,000+ participants are registered on Maiat's [ERC-8004 Identity Registry](https://basescan.org/address/0x8004A169FB4a3325136EB29fA0ceB6D2e539a432) on Base.

## Run

```bash
node synthesis/simulation.js
```

## What It Shows

1. **Cold Start** — All judges start at trust score 0. Escrow + quorum protect projects.
2. **Reputation Building** — Good judges earn trust through consistent, accurate evaluations.
3. **Natural Selection** — Bad judges (biased/inaccurate) get blocked by low trust scores.
4. **Full Auditability** — Every judgment produces an EAS attestation (on-chain receipt).

## Hooks Involved

| Hook | Role in Simulation |
|------|--------------------|
| `TrustGateACPHook` | Gates judge participation by trust score |
| `FundTransferHook` | Escrows rewards for untrusted judges |
| `TrustBasedEvaluator` | Auto-approves high-trust judges, escalates low-trust |
| `AttestationHook` | Mints EAS receipt for every judgment |
| `MaiatRouterHook` | Chains all hooks into one address per job |

## Results

See [SIMULATION_RESULTS.txt](./SIMULATION_RESULTS.txt) for full output.

**Summary:**
- 7/7 good judges reached auto-approval (score 100/100)
- 3/3 bad judges blocked (scores 0-12/100)
- 1,695 EAS attestations minted
- 184 escrow transactions (protecting projects from unknown judges)
- Cold start → trusted ecosystem in 5 rounds
