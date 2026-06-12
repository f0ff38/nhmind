# Economics — NostrHiveMind

**Связанные документы:** [README](../README.md) (корень) · [map.md](map.md) · [roadmap.md](roadmap.md) · [nostr-protocol.md](nostr-protocol.md) · [AGENTS.md](../AGENTS.md) · [github-actions.md](github-actions.md)

Формулы ROI, cost/revenue attribution и модели для первых business-модулей: **pull-oracle** (Phase 3) и **AI decision module** (Phase 5). Реализация в coordinator — Phase 4.

---

## Теоретическая рамка

Модели опираются на общую криптоэкономическую линию:

| Автор | Концепция | Применение в nhmind |
|-------|-----------|---------------------|
| **Buterin** | Mechanism design, resource pricing, collusion resistance | `maxCostPerExecution`, NIP-90 `bid`, anti-flapping, quality gates |
| **Catalini & Gans** | Cost of verification / networking | TEE-attested fetch снижает verification cost; Nostr — networking без control plane |
| **Tasca** | Token engineering, data quality incentives | Reputation + deposits для oracle feeds и AI output quality |
| **Swan** | Algorithmic trust | Attested signature в TEE заменяет institution-based trust |
| **Saleh** | Productivity → security; oracle problem | Revenue от jobs укрепляет treasury; pull-oracle переносит on-chain cost на consumer |

**Last-mile problem** (Catalini): on-chain / Nostr verification не гарантирует off-chain truth. Pull-oracle и AI-модуль обязаны публиковать **attestation metadata** (processor, TEE quote, sources) в job result — см. [nostr-protocol.md](nostr-protocol.md).

---

## Treasury

```
Treasury (ACU / USDC)  →  compute fees  →  Acurast processors
        ↑                                      │
        └──────── module net revenue ──────────┘
```

| Валюта | Назначение |
|--------|------------|
| **ACU** | Оплата compute на Acurast (canary: cACU через [faucet](https://faucet.acurast.com)) |
| **USDC** | Deploy Agent ([x402](https://docs.acurast.com/developers/deploy-agent)) для deploy без ACU-аккаунта |

**Treasury policy (Phase 4):**

- Минимальный баланс ACU: `treasury_min_acu` — pause всех модулей при падении ниже порога.
- Refill trigger: manual ops или x402 top-up coordinator deployment.
- Revenue в millisats (NIP-90 `bid`) конвертируется в ACU по курсу на `window_end` (источник курса — ops config, не Nostr).

---

## ROI модуля (общая формула)

```
net_profit = revenue_acu − cost_acu − relay_fees_acu
ROI        = net_profit / cost_acu        (если cost_acu > 0)
ROI        = +∞ (cap в scorecard: roi_max)  (если cost_acu = 0 и revenue > 0)
ROI        = 0                            (если cost_acu = 0 и revenue = 0)
```

Окно измерения: **7 дней** скользящее (canary).

| Verdict | Условие (canary) | Условие (Phase 4 anti-flapping) | Действие coordinator |
|---------|------------------|----------------------------------|----------------------|
| `promote` | ROI ≥ 1.0, стабильный `healthCheck()` | ROI ≥ **1.1**, min 24h с прошлого verdict | ↑ replicas, mainnet |
| `pause` | ROI < 1.0 или flaky health | ROI < **0.9** | stop scaling |
| `kill` | ROI < 0.5 три окна подряд или critical failure | то же | cleanup deployment |

---

## Cost attribution (общая)

| Статья | Формула | Источник данных |
|--------|---------|-----------------|
| **ACU_cost** | `Σ maxCostPerExecution × executions` + idle interval cost | Acurast deployment metrics, `acurast estimate-fee` |
| **relay_fees** | Self-hosted: amortized VPS / events; paid relay: per-event fee | Ops ledger (Selectel VM cost → ACU/month ÷ total events) |
| **revenue_acu** | См. [Revenue attribution](#revenue-attribution) | NIP-90 settled jobs + treasury conversion |

**Self-hosted relay (Phase 2 baseline):**

```
relay_fees_acu_per_module ≈ (vps_cost_acu_month / total_nostr_events_month) × module_events_month
```

На canary при одном relay и малом объёме событий `relay_fees_acu` часто ≈ 0 в scorecard (учёт — Phase 4 treasury).

---

## Revenue attribution

**Источник revenue (зафиксировано):** оплата NIP-90 jobs через tag `bid` (millisats) + опционально ACU-native settlement через treasury.

| Этап | Событие | Учёт в `revenue_acu` |
|------|---------|----------------------|
| 1 | Client публикует job request (`5900`) с `bid` | Pending (не в окне) |
| 2 | Module публикует job result (`6900`) | Pending settlement |
| 3 | Client публикует job feedback (`7000`) `status: paid` или on-chain receipt | **Зачислено** в окно `[window_start, window_end]` |

**Конвертация millisats → ACU:**

```
revenue_acu = floor(bid_millisats × msat_to_acu_rate(window_end))
```

`msat_to_acu_rate` — конфиг coordinator (не on-chain oracle в Phase 3–4); для canary допустим фиксированный ops rate.

**Альтернатива (Phase 5+):** tag `bid_acu` (string, base units ACU) — прямой учёт без конвертации.

---

## Pull-oracle module

### Парадигма

[Acurast on-demand pull oracle](https://acurast.com/blog/oracle-blockchain-acurast/from-pull-to-push-changing-oracle-paradigms/): consumer запрашивает attested price/data **по требованию**; on-chain tx cost несёт consumer, не operator.

В nhmind transport — **Nostr NIP-90** (`job_type: oracle`), execution — **Acurast TEE** (`httpGET` к price APIs, `_STD_.signers` для подписи результата).

```
Client ──5900 job──► Nostr relay ◄──6900 result── Oracle module (TEE)
                         │
                         └── Coordinator (scorecard, promote/pause/kill)
```

### Cost model

Per-job variable cost:

```
cost_job_acu = acu_execution_fee + acu_network_egress + acu_attestation_overhead
```

Per-window fixed + variable:

```
cost_acu = (interval_executions × cost_idle_acu)
         + (jobs_completed × cost_job_acu)
         + coordinator_overhead_acu
```

| Параметр | Оценка (canary) | Как измерить |
|----------|-----------------|--------------|
| `cost_job_acu` | `maxCostPerExecution` из `acurast.json` | `acurast estimate-fee` + 7d canary |
| `cost_idle_acu` | interval schedule × idle execution cost | deployment metrics |
| `acu_network_egress` | HTTP calls к N price sources | whitelist + `maxNetworkRequests` |

**Push vs pull (экономика operator):**

| Режим | Operator pays | Revenue model | Когда выгоден |
|-------|---------------|---------------|---------------|
| **Push** (interval on-chain) | ACU + on-chain tx × feeds × chains | Subscription / protocol grant | Много passive consumers, один feed |
| **Pull** (NIP-90 on-demand) | ACU per job only | Per-job `bid` | nhmind Phase 3: ROI-gated, low fixed cost |

nhmind стартует с **pull** — меньше фиксированных расходов, проще `ROI ≥ 1.0` на canary.

### Revenue model

```
revenue_acu = Σ settled_jobs ( bid_millisats × msat_to_acu_rate )
```

**Minimum viable bid (break-even per job):**

```
bid_min_millisats = ceil( (cost_job_acu + relay_fee_per_job_acu) / msat_to_acu_rate )
```

**Break-even volume (7d window):**

```
jobs_break_even = ceil( fixed_cost_7d_acu / (bid_avg_millisats × msat_to_acu_rate − cost_job_acu) )
```

где `fixed_cost_7d_acu = cost_acu − jobs_completed × cost_job_acu` (idle + coordinator).

**Пример (illustrative, canary):**

| Параметр | Значение |
|----------|----------|
| `cost_job_acu` | 50 000 (placeholder — заменить после `estimate-fee`) |
| `cost_idle_7d_acu` | 200 000 |
| `bid_avg` | 100 000 msats |
| `msat_to_acu_rate` | 1 msat = 10 ACU base units |
| Revenue per job | 1 000 000 ACU units |
| Net per job | 950 000 |
| **jobs_break_even** | ceil(200 000 / 950 000) = **1 job / 7d** (+ idle already paid) |

> Цифры placeholder до первого canary-deploy oracle-модуля. Exit criteria Phase 3: заменить на measured `cost_job_acu`.

### Quality & incentives (Tasca)

Oracle без quality gate масштабирует bad data. Минимальный stack:

| Механизм | Реализация | Эффект |
|----------|------------|--------|
| **Multi-source median** | ≥3 API sources в bundle logic | Снижает manipulation |
| **NIP-90 feedback** | kind `7000`, `status: rejected` + reason | Reputation signal |
| **Processor reputation** | `minProcessorReputation` в `acurast.json` | Acurast-native filter |
| **Deposit (Phase 5+)** | Client escrow → slash on bad attestation | Economic penalty |

**Quality-adjusted revenue (Phase 5):**

```
revenue_adjusted_acu = revenue_acu × (1 − slash_rate) − dispute_refunds_acu
```

`slash_rate` — доля jobs с `feedback: rejected` за окно (cap 0.3 для canary).

### Scaling policy

| ROI (7d) | Replicas | Network |
|----------|----------|---------|
| < 0.9 | 1 | canary, pause scaling |
| 0.9 – 1.1 | 1 | canary, observe |
| ≥ 1.1 | min(⌈jobs_peak_hour / capacity⌉, max_replicas) | promote → mainnet |

`capacity` — из heartbeat `capacity.max_concurrent_jobs`.

### `getMetrics()` (pull-oracle)

```typescript
interface OracleModuleMetrics {
  revenueAcu: bigint;      // settled NIP-90 bids → ACU
  costAcu: bigint;         // ACU spent (executions + idle)
  jobsCompleted: number;
  jobsRejected: number;
  avgLatencyMs: number;
  windowStart: number;
  windowEnd: number;
}
```

---

## AI decision module

### Парадигма

Business-модуль с **confidential LLM inference** в TEE (`requiredModules` для LLM). Принимает structured input (NIP-44), возвращает signed decision/recommendation — не просто data fetch, а **compute-heavy judgment**.

Связь с [NodeGhost × Acurast experiment](https://acurast.com/blog/partnerships/decentralized-confidential-ai-inference-powered-by-smartphones/): sustained inference на attested devices доказан; nhmind добавляет Nostr coordination + ROI loop.

```
Client ──5900 job──► Nostr ◄──6900 result── AI module (TEE + LLM)
  (NIP-44 input)              (signed decision + optional NIP-44 output)
```

### Cost model

AI jobs значительно дороже oracle fetch:

```
cost_job_acu = acu_base_execution
             + acu_llm_module_fee          // requiredModules LLM surcharge
             + acu_memory × token_count    // variable by payload
             + acu_network_egress
```

**Multidimensional pricing** (Buterin): лимиты в `acurast.json`:

```json
{
  "usageLimit": {
    "maxMemory": "<worst_case_tokens>",
    "maxNetworkRequests": "<context_fetch_limit>",
    "maxStorage": 0
  },
  "maxExecutionTimeInMs": "<worst_case_inference_ms>",
  "maxCostPerExecution": "<hard_cap_acu>"
}
```

Per-window:

```
cost_acu = idle_cost_7d + Σ(jobs × cost_job_acu(tokens_in, tokens_out))
```

| Tier | `job_type` tag | Typical `maxCostPerExecution` | Latency SLA |
|------|----------------|--------------------------------|-------------|
| **Light** | `ai-classify` | Low (classification) | < 5s |
| **Standard** | `ai-decide` | Medium (short CoT) | < 30s |
| **Heavy** | `ai-plan` | High (multi-step) | < 120s |

Tier выбирается client через `t` capability tags; module advertises tiers в heartbeat.

### Revenue model

**Premium за confidential inference** — bid выше публичного API equivalent:

```
bid_recommended_millisats = api_equivalent_price × confidentiality_premium × quality_multiplier
```

| Factor | Range | Rationale |
|--------|-------|-----------|
| `confidentiality_premium` | 1.2 – 2.0× | TEE: prompts не логируются (Swan: algorithmic trust) |
| `quality_multiplier` | 0.8 – 1.2× | Feedback score rolling 7d |

**Break-even:**

```
jobs_break_even = ceil( fixed_cost_7d_acu / (bid_avg_acu − avg_cost_job_acu) )
```

AI-модули имеют **выше fixed_cost** (LLM module idle) → нужен больший volume или выше bid, чем pull-oracle.

### Quality-adjusted ROI

Raw ROI недостаточен: promote при плохих decisions масштабирует вред (Buterin: futarchy / prediction-style feedback).

```
quality_score = 1 − (rejected_jobs / completed_jobs)     // clamp [0.5, 1.0]
ROI_quality   = ROI × quality_score
```

| Verdict | Условие (AI module) |
|---------|---------------------|
| `promote` | `ROI_quality ≥ 1.1` AND `quality_score ≥ 0.85` AND stable health |
| `pause` | `ROI_quality < 0.9` OR `quality_score < 0.75` |
| `kill` | `quality_score < 0.5` три окна OR critical safety failure |

**Feedback loop:** NIP-90 kind `7000` — client или delegated reviewer; optional NIP-44 encrypted critique.

### Collusion & gaming

| Risk | Mitigation |
|------|------------|
| Sybil positive feedback | Feedback только от pubkeys с prior settled jobs |
| Self-dealing (module bids own jobs) | Coordinator exclude same-pubkey requester=worker |
| Goodhart (optimize score, not quality) | Multifactorial: ROI + quality + latency + uptime (Buterin governance) |

### Scaling policy

Conservative vs oracle — LLM cost variance выше:

| ROI_quality (7d) | Replicas | Action |
|------------------|----------|--------|
| < 1.0 | 1 | pause |
| 1.0 – 1.2 | 1 | observe (no promote) |
| ≥ 1.2 | +1 replica per window, max 3 | promote (canary → mainnet after 2 windows) |

Anti-flapping: min **48h** между replica changes для AI module (vs 24h generic).

### `getMetrics()` (AI module)

```typescript
interface AiModuleMetrics {
  revenueAcu: bigint;
  costAcu: bigint;
  jobsCompleted: number;
  jobsRejected: number;
  avgTokensIn: number;
  avgTokensOut: number;
  avgLatencyMs: number;
  qualityScore: number;    // 0..1
  windowStart: number;
  windowEnd: number;
}
```

---

## Сравнение модулей

| | Pull-oracle | AI decision module |
|---|-------------|-------------------|
| Phase | 3 (first business module) | 5 (experimental) |
| `job_type` | `oracle` | `ai-decide`, `ai-classify`, `ai-plan` |
| Dominant cost | HTTP fetch + sign | LLM inference + memory |
| Revenue driver | Per-fetch bid | Premium confidential inference |
| Quality gate | Multi-source + feedback | quality_score × ROI |
| Break-even volume | Lower | Higher |
| Promote threshold | ROI ≥ 1.1 | ROI_quality ≥ 1.1 + quality ≥ 0.85 |
| Push alternative | Not in nhmind v1 | N/A |

---

## Module Scorecard (Nostr)

Coordinator публishes replaceable event (NIP-33), kind `30091` — см. [nostr-protocol.md](nostr-protocol.md).

Обязательные поля:

- `module_id`, `window_start`, `window_end`
- `revenue_acu`, `cost_acu`, `relay_fees_acu`, `roi`
- `verdict`: `promote` | `pause` | `kill`
- `deployment_id` (Acurast)

**Расширения (Phase 4+, optional tags в content JSON):**

| Поле | Модули | Описание |
|------|--------|----------|
| `jobs_completed` | oracle, AI | Count settled jobs |
| `quality_score` | AI | 0..1 |
| `roi_quality` | AI | Quality-adjusted ROI |
| `module_tier` | AI | Dominant tier in window |

---

## Productivity → security (Saleh)

Treasury и module revenue — не только ROI loop, но и **economic productivity** сети:

```
network_productivity_acu = Σ_modules revenue_acu − Σ_modules external_subsidies
```

Чем выше sustained `network_productivity_acu`, тем оправданнее:

- mainnet promotion (real demand, not faucet-only)
- увеличение `numberOfReplicas`
- привлечение external clients (не только ops treasury)

Faucet cACU = **subsidy**; модуль на mainnet должен target `network_productivity_acu > 0` за 7d.

---

## Implementation checklist

| Item | Phase | Status |
|------|-------|--------|
| ROI formula in coordinator | 4 | ⬜ stub (`revenue_acu: "0"`) |
| NIP-90 bid → revenue_acu conversion | 4 | ⬜ |
| Measured `cost_job_acu` (oracle) | 3 | ⬜ needs canary deploy |
| `quality_score` in scorecard | 5 | ⬜ |
| Treasury min balance gate | 4 | ⬜ |

---

## References

- Buterin, V. — [A Proof of Stake Design Philosophy](https://medium.com/@VitalikButerin/a-proof-of-stake-design-philosophy-506585978d51); [Blockchain Resource Pricing](https://ethresear.ch/t/blockchain-resource-pricing/804); [On Collusion](https://vitalik.eth.link/general/2019/04/03/collusion.html)
- Catalini, C. & Gans, J. S. — [Some Simple Economics of the Blockchain](https://www.nber.org/papers/w22952) (NBER 2016)
- Tasca, P. et al. — [Incentivizing Data Quality in Blockchain-Based Systems](https://dl.acm.org/doi/10.1145/3538228); *Blockchain Economics* (World Scientific, 2019)
- Swan, M. — [Blockchain Economic Networks and Algorithmic Trust](https://aisel.aisnet.org/amcis2018/Philosophy/Presentations/4/); *Cryptoeconomic Theory* (World Scientific, 2026)
- Saleh, F. — [Blockchain Without Waste: Proof-of-Stake](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3183935); [Smart Contracts and DeFi](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4222528)
- Acurast — [From Pull to Push: Oracle Paradigms](https://acurast.com/blog/oracle-blockchain-acurast/from-pull-to-push-changing-oracle-paradigms/); [Confidential AI on Smartphones](https://acurast.com/blog/partnerships/decentralized-confidential-ai-inference-powered-by-smartphones/)
