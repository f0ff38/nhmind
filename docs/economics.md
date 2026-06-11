# Economics — NostrHiveMind

**Связанные документы:** [README](../README.md) (корень) · [map.md](map.md) · [roadmap.md](roadmap.md) · [AGENTS.md](../AGENTS.md) · [github-actions.md](github-actions.md)

Черновик формул и правил. Детализация — в Phase 3–4 [roadmap](roadmap.md).

## Treasury

```
Treasury (ACU / USDC)  →  compute fees  →  Acurast processors
        ↑                                      │
        └──────── module net revenue ──────────┘
```

- **ACU** — оплата compute на Acurast (canary: cACU через [faucet](https://faucet.acurast.com))
- **USDC** — альтернатива через [Deploy Agent](https://docs.acurast.com/developers/deploy-agent) (x402)

## ROI модуля

```
ROI = (revenue − ACU_cost − relay_fees) / ACU_cost
```

Окно измерения: **7 дней** скользящее (canary).


| Verdict   | Условие                                        | Действие coordinator |
| --------- | ---------------------------------------------- | -------------------- |
| `promote` | ROI ≥ 1.0, стабильный `healthCheck()`          | ↑ replicas, mainnet  |
| `pause`   | ROI < 1.0 или flaky health                     | stop scaling         |
| `kill`    | ROI < 0.5 три окна подряд или critical failure | cleanup deployment   |


### Anti-flapping (Phase 4)

- Promote только если ROI ≥ **1.1**
- Pause если ROI < **0.9**
- Минимум **24h** между сменами verdict для одного модуля

## Cost attribution


| Статья     | Источник данных                                           |
| ---------- | --------------------------------------------------------- |
| ACU_cost   | `acurast deployments`, `maxCostPerExecution` × executions |
| relay_fees | TBD (платные relays / self-hosted)                        |
| revenue    | TBD per module (on-chain events, API settlement)          |


## Module Scorecard (Nostr)

Coordinator публикует replaceable event (NIP-33) с полями:

- `module_id`, `window_start`, `window_end`
- `revenue_acu`, `cost_acu`, `roi`
- `verdict`: `promote` | `pause` | `kill`
- `deployment_id` (Acurast)

Схема событий — см. `docs/nostr-protocol.md` (Phase 1).