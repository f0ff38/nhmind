# Roadmap — NostrHiveMind

Живой план развития. Статус обновляется по мере закрытия фаз.

**Связанные документы:** [README](../README.md) · [AGENTS.md](../AGENTS.md) · [github-actions.md](github-actions.md)

---

# NostrHiveMind

Децентрализованная сеть автономных AI-агентов:

- **Исполнение** — Acurast deployments в hardware TEE
- **Координация** — гибрид: Nostr (публичный слой) + Acurast mesh `_STD_.ws` (внутренний горячий путь)
- **Экономика** — ROI-gated autoscaling, treasury ACU/USDC

```mermaid
flowchart LR
  P0[Phase 0\nFoundation] --> P1[Phase 1\nNostr layer]
  P1 --> P2[Phase 2\nCoordinator]
  P2 --> P3[Phase 3\nFirst module]
  P3 --> P4[Phase 4\nEconomics]
  P4 --> P5[Phase 5\nProduction]
```



---

## Текущее состояние — v0.4 (Phase 2 — closing)


| Компонент                                                    | Статус                         |
| ------------------------------------------------------------ | ------------------------------ |
| Архитектура и README                                         | ✅                              |
| Docker-only dev (`scripts/dev`, compose, Dev Container)      | ✅                              |
| Стартовый модуль `modules/hello`                             | ✅                              |
| Scaffold `modules/module-template` + `scripts/new-module.sh` | ✅                              |
| GitHub Actions CI (`verify` + scaffold job)                  | ✅                              |
| GitHub Actions `deploy-canary.yml`                           | ✅                              |
| Cursor: `AGENTS.md`, `.cursor/environment.json`, `BUGBOT.md` | ✅                              |
| Roadmap / economics docs                                     | ✅                              |
| **Активная фаза**                                            | **Phase 2 — Coordinator**      |
| `packages/nostr-client`                                      | ✅ Phase 1                       |
| `modules/coordinator` (код)                                  | ✅                              |
| `hello` canary на processor                                  | ✅ (deploy via GHA)              |
| `coordinator` canary на processor                            | ⬜ следующий шаг                 |
| Публичный relay + `RELAY_URL` в deploy                       | ⬜ блокер exit criteria Phase 2 |


---

## Phase 0 — Foundation

**Цель:** воспроизводимая среда разработки и CI без зависимости от хостового Node.

### Deliverables

- [x] Docker + `scripts/dev` + `.devcontainer`
- [x] `modules/hello` — эталон Acurast-модуля (webpack, vitest, `acurast.json`)
- [x] Mock `_STD_` для локального прогона
- [x] CI: test → bundle → smoke
- [x] Cursor / GitHub integration docs
- [x] Merge foundation PR в `main`
- [x] `modules/module-template` + `scripts/new-module.sh`
- [x] CI matrix (hello + module-template) + scaffold smoke job
- [x] Branch protection на `main` ✅

### Exit criteria

- [x] Любой разработчик с Docker + Cursor клонирует репо и проходит `./scripts/dev test` без ручной настройки Node
- [x] CI зелёный на `main` (после merge)
- [x] Новый модуль создаётся одной командой: `./scripts/new-module.sh <name>`

**Phase 0 — завершена.** Дальше: Phase 1.

---

## Phase 1 — Nostr layer

**Цель:** общая библиотека координации и зафиксированная схема событий.

### Deliverables

- [x] `docs/nostr-protocol.md` — kinds, tags, примеры payload
- [x] `packages/nostr-client` — publish/subscribe, NIP-44, NIP-90 helpers
- [x] NIP-33 replaceable events — agent heartbeat (`30090`; scorecard `30091` — Phase 2)
- [x] Интеграционные тесты против `nostr-relay` в compose
- [x] `hello` публикует heartbeat в relay (dev)

### Exit criteria

- [x] Модуль может опубликовать и прочитать своё replaceable-событие через локальный relay
- [x] Схема событий задокументирована и покрыта тестами

**Phase 1 — завершена.** Дальше: Phase 2.

### Риски

- Eventual consistency между relays — заложить last-signed-wins в coordinator (Phase 2)

---

## Phase 2 — Coordinator

**Цель:** deployment на Acurast, который читает Nostr и управляет жизненным циклом модулей.

### Deliverables

- [x] `modules/coordinator` — interval deployment, `@acurast/sdk` (deploy stub in bundle)
- [x] Регистрация модулей (Nostr event → known module list)
- [x] Scorecard aggregator (метрики из module events — stub metrics)
- [x] Verdict engine: `promote` | `pause` | `kill` (правила без on-chain revenue пока — stub metrics)
- [x] Programmatic deploy через SDK (canary) — `deploy-canary.yml` + `scripts/deploy-acurast-sdk.mjs`; autoscale в TEE — Phase 4
- [ ] Canary deploy **coordinator** + smoke на processor
- [x] Canary deploy **hello** на processor (GHA)

### Exit criteria

- Coordinator публикует scorecard в Nostr
- Может зарегистрировать `hello` как модуль и выставить verdict `pause` без human intervention (кроме первого deploy)

### Зависимости

- Phase 1 (nostr-client)
- Funded canary wallet + manual first deploy
- Собственный Nostr relay (`RELAY_URL`) — VPS, поддомен, DNS TXT `_acu.<host>` (см. [nostr-protocol.md](nostr-protocol.md#nostr-relay-на-canary-ops))

### Координация (гибрид)

| Слой | Статус | Заметка |
|------|--------|---------|
| Nostr (NIP-33/90) | ✅ код Phase 1–2 | Exit criteria Phase 2 — на этом слое |
| `_STD_.ws` mesh | ⬜ Phase 3+ | Срочные команды coordinator ↔ module; те же `nhmind/*/v1` схемы |

---

## Phase 3 — First business module

**Цель:** модуль с реальной (пусть небольшой) экономической логикой, прошедший canary-цикл.

### Deliverables

- [ ] `_STD_.ws` mesh: coordinator → module команды (`pause`/`kill` ack), env `WSS_URLS` / canary proxies
- [ ] Выбор experimental-модуля (oracle, API relay, простой DVM job — не GameFi/MEV на старте)
- [ ] `modules/<name>/` — `IBusinessModule`, production-shaped `acurast.json`
- [ ] Реальные `_STD_.signers` / `httpGET` на canary processor
- [ ] DevTools-enabled deploy, логи проверены
- [ ] 7-дневное canary-окно измерений (ручной или coordinator stub)
- [ ] `docs/economics.md` — формулы ROI, cost attribution

### Exit criteria

- Модуль выполняется на canary processor без mock `_STD_`
- `healthCheck()` и `getMetrics()` возвращают реальные данные
- Документирован фактический ACU cost per execution

### Риски

- DNS TXT whitelist для внешних API — может потребовать отдельный домен
- `acurast live` + телефон для отладки до canary deploy

---

## Phase 4 — Economics & autoscaling

**Цель:** замкнуть петлю «revenue → ROI → scale».

### Deliverables

- [ ] Treasury tracking (ACU balance, spend per module)
- [ ] ROI расчёт: `(revenue − ACU_cost − relay_fees) / ACU_cost` за окно 7d
- [ ] Coordinator autoscaling: `promote` → `numberOfReplicas↑`, `kill` → cleanup
- [ ] Anti-flapping (hysteresis: promote при ROI ≥ 1.1, pause при ROI < 0.9)
- [x] GitHub workflow `deploy-canary.yml` (`workflow_dispatch`, secrets)
- [ ] Опционально: Deploy Agent (x402) для coordinator без ACU-аккаунта

### Exit criteria

- Хотя бы один модуль прошёл полный цикл: `register → canary → measure → promote | pause`
- Autoscaling срабатывает только при `promote`

### Зависимости

- Phase 2 + Phase 3
- Источник revenue (on-chain или off-chain attribution) — зафиксировать в `economics.md`

---

## Phase 5 — Production hardening

**Цель:** mainnet-ready операции без centralized control plane.

### Deliverables

- [ ] `mutability: Immutable` для production-модулей
- [ ] `minProcessorReputation` / `processorWhitelist` для sensitive workloads
- [ ] Mainnet deploy coordinator + validated modules
- [ ] LLM inference module (experimental) — `requiredModules`, confidential inference
- [ ] Path filters в CI для monorepo
- [ ] Публичный relay-лист + fallback strategy
- [ ] Runbook: incident pause, treasury refill, key rotation (`reuseKeysFrom`)

### Exit criteria

- Coordinator + ≥1 модуль на mainnet с `ROI ≥ 1.0` или осознанный `pause`
- Нет секретов в git; deploy только через secrets / TEE env

---

## Backlog (после Phase 5)


| Идея                           | Заметка                                         |
| ------------------------------ | ----------------------------------------------- |
| GameFi / MEV modules           | High-risk; только после стабильного coordinator |
| NIP-AC / agent swarm           | Если стандартизируется в экосистеме Nostr       |
| Multi-relay quorum             | Снижение зависимости от одного relay            |
| Relay allowlist (kinds/tags/pubkeys) | Из практики Nosflare → `nostr-rs-relay` config + nginx rate limit; см. [relay-ops.md](relay-ops.md) |
| `infra/nostr-relay` + `deploy-relay.yml` | VPS bootstrap из репо (ожидаем домен/IP/SSH) |
| `packages/module-template` CLI | `npx create-nhmind-module`                      |
| Cursor Automations             | PR opened → review; CI failed → agent fix       |


---

## Как пользоваться роадмапом

1. **Перед началом фазы** — создать GitHub milestone `Phase N` и issues по deliverables.
2. **При закрытии deliverable** — отметить `[x]` в этом файле (отдельный PR).
3. **Агентам (Cursor)** — брать задачи только из текущей открытой фазы, если не указано иное.
4. **Не перескакивать** Phase 3 (real TEE) без Phase 1–2 — иначе нет координации и схемы событий.

---

## Метрики успеха (сквозные)


| Метрика                      | Целевое значение                        |
| ---------------------------- | --------------------------------------- |
| CI `verify`                  | Зелёный на каждый PR                    |
| Bundle size (hello baseline) | Контроль роста < 500 KB gzip (ориентир) |
| Module ROI                   | ≥ 1.0 для `promote`                     |
| Centralized servers in prod  | 0                                       |
| Secrets in repo              | 0                                       |


