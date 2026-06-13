# NostrHiveMind (nhmind)

Децентрализованная система AI-агентов: **исполнение в TEE на [Acurast](https://docs.acurast.com/)**, **координация через [Nostr](https://github.com/nostr-protocol/nips)**.

> Репозиторий: [github.com/f0ff38/nhmind](https://github.com/f0ff38/nhmind)

**Это корневой файл проекта.** Начинайте здесь — обзор, архитектура, dev-цикл и навигация по документации.

**Агенты (Cursor Cloud, Automations, CLI):** [README.md](README.md) (этот файл) → [AGENTS.md](AGENTS.md) (правила, проверки, PR) → [roadmap](docs/roadmap.md) (фаза, checkpoint) → [map](docs/map.md) (остальные docs).

---

## Документация

**Иерархия:** [README](README.md) (корень) → [AGENTS.md](AGENTS.md) (агенты) → [roadmap](docs/roadmap.md) (план, checkpoint) → [map](docs/map.md) и спец. docs.


| Уровень | Документ                                         | Зачем                                                 |
| ------- | ------------------------------------------------ | ----------------------------------------------------- |
| 0       | **README.md** (этот файл)                        | Обзор, архитектура, локальная разработка              |
| 0       | [AGENTS.md](AGENTS.md)                           | **Агенты:** правила, `./scripts/dev`, PR, секреты — после README |
| 1       | [docs/roadmap.md](docs/roadmap.md)               | Фазы, статус, **следующая сессия**                    |
| 2       | [docs/map.md](docs/map.md)                       | **Карта всей документации** — поддерживать актуальной |
| 2       | [docs/nostr-protocol.md](docs/nostr-protocol.md) | Nostr kinds, схемы, Acurast transport                 |
| 2       | [docs/relay-ops.md](docs/relay-ops.md)           | Relay VPS, Selectel GitOps                            |
| 2       | [docs/github-actions.md](docs/github-actions.md) | CI, canary, relay workflows                           |
| 2       | [docs/economics.md](docs/economics.md)           | ROI, treasury (Phase 3–4)                             |


**При изменении docs в PR:** обновите [docs/map.md](docs/map.md) и при смене статуса/фазы — [roadmap](docs/roadmap.md). Правила — в [map.md § обновление](docs/map.md#правила-обновления-карты-агенты-и-pr).

---

## Цель

Сеть автономных агентов, где каждый бизнес-модуль — отдельный **Acurast deployment** (serverless job в hardware TEE), а обмен задачами и статусами идёт через Nostr без централизованного control plane.

Три обязательных принципа:

1. **Самоокупаемость** — модуль масштабируется только при `ROI ≥ 1.0` за скользящее окно измерений.
2. **Децентрализация исполнения** — compute и секреты только в TEE; в production нет собственных серверов и БД.
3. **Плагинные модули** — единый контракт `IBusinessModule`, независимые bundle-деплои.

---

## Архитектура

```
┌─────────────────────────────────────────────────────────────┐
│  Nostr (координация, eventual consistency)                  │
│  NIP-90 jobs · NIP-44 шифрование · NIP-33 replaceable state │
└──────────────────────────┬──────────────────────────────────┘
                           │ publish / subscribe
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│ Coordinator   │  │ Business      │  │ Business      │
│ deployment    │  │ module A      │  │ module B      │
│ (Acurast TEE) │  │ (Acurast TEE) │  │ (Acurast TEE) │
└───────┬───────┘  └───────┬───────┘  └───────┬───────┘
        │                  │                  │
        └──────────────────┴──────────────────┘
                           │
              programmatic deploy / scale
              (@acurast/sdk · Deploy Agent x402)
```

### Роли компонентов


| Компонент           | Где живёт                                       | Назначение                                                                              |
| ------------------- | ----------------------------------------------- | --------------------------------------------------------------------------------------- |
| **Coordinator**     | Acurast deployment (`interval`)                 | Читает Nostr, ведёт scorecard модулей, регистрирует/останавливает deployments через SDK |
| **Business module** | Отдельный Acurast deployment на модуль          | Доходная логика; реализует `IBusinessModule`                                            |
| **Nostr relays**    | Собственный relay (`RELAY_URL` на вашем домене) | Публичный event bus: heartbeat, scorecard, registry, NIP-90 jobs                        |
| **Acurast mesh**    | `_STD_.ws` (websocket-proxy Acurast)            | Прямые команды coordinator ↔ module; без своего VPS                                     |


### Гибридная координация

Два канала, **одни и те же JSON-схемы** (`nhmind/*/v1`, см. [nostr-protocol.md](docs/nostr-protocol.md)):


| Канал            | Транспорт                                       | Для чего                                                       | Ops                                              |
| ---------------- | ----------------------------------------------- | -------------------------------------------------------------- | ------------------------------------------------ |
| **Nostr**        | `RELAY_URL` → `httpGET`/`httpPOST` на processor | Replaceable state (NIP-33), внешние NIP-90 jobs, наблюдаемость | VPS + поддомен + DNS TXT `_acu.<host>`           |
| **Acurast mesh** | `_STD_.ws.open` / `send(recipient, …)`          | Срочные команды, low-latency ack между deployments             | Нативная инфра Acurast (не путать с Nostr relay) |


**Phase 2 (сейчас):** exit criteria — на **Nostr**. `**_STD_.ws`** — Phase 3+ ([roadmap](docs/roadmap.md)).

Acurast P2P relays (`relay-*.canary.acurast.com`) и Substrate RPC (`public-rpc.canary.acurast.com`) — **не** `RELAY_URL`.

### Жизненный цикл модуля

```
register → canary (1 replica, canary network) → measure (7d) → score → promote | pause | kill
```

- **promote** — увеличить `numberOfReplicas`, перейти на `mainnet`, interval-schedule.
- **pause** — `numberOfExecutions: 0` / cleanup deployment.
- **kill** — `acurast deployments --cleanup`.

---

## Почему не «state bus на Nostr»

Nostr — **event log с eventual consistency**, не база данных. В проекте:


| Данные                              | Где хранятся                                                                                                 |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Задачи, результаты, feedback        | [NIP-90](https://github.com/nostr-protocol/nips/blob/master/90.md) (kind `5000–5999` / `6000–6999` / `7000`) |
| Статус агента, capacity, pricing    | Parameterized replaceable events ([NIP-33](https://github.com/nostr-protocol/nips/blob/master/33.md))        |
| Конфиденциальные payload            | [NIP-44](https://nips.nostr.com/44)                                                                          |
| Scorecard, ROI, решения coordinator | События coordinator + on-chain метрики ACU/revenue                                                           |
| Секреты, ключи подписи              | TEE: `_STD_.signers` + `_STD_.env`                                                                           |


Конфликты между relays разрешаются правилами coordinator (last-signed-wins по `created_at` + pubkey).

---

## Acurast: обязательные практики

Официальная модель: **bundle → `acurast.json` → deploy**. Каждый модуль — самостоятельный проект с одним `dist/bundle.js`.

### Сборка и runtime

- Target runtime: **Node.js v20** (процессоры Acurast). Локально — тот же major.
- Код упаковывается в **один JS-bundle** (Webpack/esbuild); зависимости внутри bundle, не на processor.
- Минимизировать размер bundle: tree-shaking, без тяжёлых native-модулей.

### `acurast.json` (production defaults)

```json
{
  "onlyAttestedDevices": true,
  "mutability": "Immutable",
  "assignmentStrategy": { "type": "Single" },
  "includeEnvironmentVariables": ["..."],
  "usageLimit": {
    "maxMemory": 0,
    "maxNetworkRequests": 0,
    "maxStorage": 0
  }
}
```


| Параметр                 | Рекомендация                                                         |
| ------------------------ | -------------------------------------------------------------------- |
| `onlyAttestedDevices`    | `true` — только attested hardware                                    |
| `mutability`             | `Immutable` в production; `Mutable` только для dev и `reuseKeysFrom` |
| `network`                | `canary` → после валидации `mainnet`                                 |
| `execution.type`         | `interval` для агентов; `onetime` для разовых job                    |
| `maxExecutionTimeInMs`   | Задавать явно под worst-case сценарий модуля                         |
| `maxCostPerExecution`    | Всегда лимитировать; оценка через `acurast estimate-fee`             |
| `startAt.msFromNow`      | Canary/CI: **`300000`** (5 мин, как дефолт CLI). Не ставить `0` (chain reject) и не `60000` — processors не успевают match до Start → Hub **Expired** |
| `minProcessorReputation` | Поднимать для production-модулей                                     |
| `processorWhitelist`     | Для canary и чувствительных модулей                                  |
| `requiredModules`        | `['DataEncryption']` при работе с секретами                          |

Canary deploy из GHA: [deploy-canary-acurast.sh](scripts/deploy-canary-acurast.sh) регистрирует job on-chain и **не ждёт** processor match (до 5 min); smoke на relay проверяет execution. Hub: [hub.acurast.com](https://hub.acurast.com/) — сеть **Canary**, кошелёк = адрес из `ACURAST_MNEMONIC_*`.


### Секреты и подпись (вместо отдельного «vault»)

Отдельный vault-микросервис **не используется**. Acurast даёт TEE-native API:

- **Подпись** — `_STD_.signers.secp256k1` / `secp256r1` / `ed25519` (ключи deployment, не покидают enclave).
- **Секреты** — `.env` + `includeEnvironmentVariables`; доступ в runtime через `_STD_.env`.
- **Идентичность между деплоями** — `reuseKeysFrom` только от `Mutable` deployment.

Запрещено: приватные ключи, мнемоники и API-токены в исходном коде или в bundle.

### Сеть

- Исходящие HTTP — через `httpGET` / `httpPOST` runtime API.
- Для whitelist хостов — `_STD_.network.whitelist()` с DNS TXT-верификацией (`_acu.<host>`).
- Публичные HTTP-сервисы — `*.acu.run` reverse proxy или `_STD_.tunnel`.

### Разработка и деплой


| Этап                    | Инструмент (в Docker через `./scripts/dev`)                                           |
| ----------------------- | ------------------------------------------------------------------------------------- |
| Scaffold                | `npx @acurast/cli new <module>` внутри контейнера                                     |
| Bundle                  | `./scripts/dev bundle`                                                                |
| Локальная отладка       | `./scripts/dev run`, затем `acurast live`                                             |
| Тесты                   | `./scripts/dev test`                                                                  |
| Canary                  | `./scripts/dev acurast deploy`                                                        |
| Production              | `network: mainnet` + deploy или [@acurast/sdk](https://docs.acurast.com/)             |
| Оплата без ACU-аккаунта | [Deploy Agent](https://docs.acurast.com/developers/tools/deploy-agent) (x402, USDC на Base) |
| LLM inference           | `requiredModules` для LLM; confidential inference в TEE                               |


### Масштабирование

Autoscaling **не встроен в Acurast** — его реализует Coordinator deployment:

1. Читает scorecard и verdict модуля.
2. Вызывает SDK / Deploy Agent с обновлённым `numberOfReplicas` или новым job spec.
3. Пишет решение в Nostr (replaceable event).

---

## Экономика

```
Treasury (ACU / USDC)  →  compute fees  →  Acurast processors
        ↑                                      │
        └──────── module net revenue ──────────┘
```

- Операционная валюта: **ACU** (compute) и **USDC** (Deploy Agent).
- ROI модуля: `(revenue − ACU_cost − relay_fees) / ACU_cost` за окно 7 дней.
- Масштабирование gated: только `promote` при `ROI ≥ 1.0` и стабильном `healthCheck()`.

---

## Контракт модуля

```typescript
interface IBusinessModule {
  healthCheck(): Promise<{ ok: boolean; details?: string }>;
  getMetrics(): Promise<ModuleMetrics>; // revenue, cost, executions
}

interface ModuleMetrics {
  revenueAcu: bigint;
  costAcu: bigint;
  windowStart: number;
  windowEnd: number;
}
```

Coordinator агрегирует метрики и публикует scorecard. Стартовые experimental-модули (GameFi, MEV и др.) подключаются через этот интерфейс без изменения ядра.

---

## Локальная разработка (только Docker)

На хосте нужны **Docker Desktop**, **Cursor** и **git**. Node.js и npm на машине не требуются.

Официальный цикл Acurast выполняется в контейнере:

```
bundle → run (mock _STD_) → test → acurast init → faucet → deploy → devtools/live
```

### Быстрый старт

```bash
git clone https://github.com/f0ff38/nhmind.git
cd nhmind
cp .env.example .env

./scripts/dev up          # dev + nostr-relay (profile relay)
./scripts/dev install     # npm ci в modules/hello
./scripts/dev bundle      # dist/bundle.js
./scripts/dev run         # локальный прогон (mock _STD_)
./scripts/dev test        # unit-тесты
./scripts/new-module.sh my-module   # scaffold из module-template
```

### Acurast CLI (в контейнере)

```bash
./scripts/dev acurast init            # acurast.json + .env (mnemonic)
./scripts/dev acurast estimate-fee
./scripts/dev acurast deploy          # canary, см. modules/hello/acurast.json
./scripts/dev acurast live --setup    # один раз: processor снаружи (телефон)
./scripts/dev acurast live            # отладка на live-processor
```

После deploy с `enableDevtools: true` CLI выдаёт URL веб-дашборда с логами.

### Cursor Dev Container

Откройте репозиторий в Cursor → **Reopen in Container**. Терминал и зависимости уже внутри `dev`-сервиса.

### Cursor + GitHub

1. [Dashboard → Integrations → GitHub](https://cursor.com/dashboard/integrations) — подключить `f0ff38/nhmind`
2. [Bugbot](https://cursor.com/dashboard/bugbot) — авто-ревью PR (правила: `.cursor/BUGBOT.md`)
3. Cloud Agents — `@cursor` в issue/PR или [cursor.com/agents](https://cursor.com/agents)
4. Инструкции для агентов: `[AGENTS.md](AGENTS.md)`, окружение: `[.cursor/environment.json](.cursor/environment.json)`

### GitHub Actions


| Workflow                                                                     | Триггер             | Назначение                                                 |
| ---------------------------------------------------------------------------- | ------------------- | ---------------------------------------------------------- |
| `[ci.yml](.github/workflows/ci.yml)`                                         | push/PR → `main`    | test + bundle + smoke (hello, coordinator, template)       |
| `[deploy-canary.yml](.github/workflows/deploy-canary.yml)`                   | `workflow_dispatch` | canary deploy hello / coordinator (environment **canary**) |
| `[validate-relay-secrets.yml](.github/workflows/validate-relay-secrets.yml)` | `workflow_dispatch` | проверка секретов environment **relay**                    |
| `[provision-relay-infra.yml](.github/workflows/provision-relay-infra.yml)`   | `workflow_dispatch` | Terraform: Selectel VM, сеть, floating IP, PTR             |


CI и branch protection: `[docs/github-actions.md](docs/github-actions.md)`. Relay GitOps: environment **relay** — см. [relay-ops.md](docs/relay-ops.md). Canary: **canary** + `ACURAST_MNEMONIC_*`, `RELAY_HOSTNAME` (→ `RELAY_URL` в deploy-canary).

### Что остаётся вне Docker


| Шаг                   | Где выполняется                                            |
| --------------------- | ---------------------------------------------------------- |
| `acurast live`        | CLI в контейнере, **processor на телефоне**                |
| TEE / `_STD_.signers` | Только на Acurast processor (canary deploy)                |
| Faucet cACU           | Браузер → [faucet.acurast.com](https://faucet.acurast.com) |


---

## Структура репозитория

```
nhmind/
├── AGENTS.md
├── Dockerfile / docker-compose.yml
├── scripts/
│   ├── dev                       # обёртка без npm на хосте
│   ├── new-module.sh
│   ├── show-acurast-address.mjs  # адрес deploy-кошелька из .env
│   └── deploy-acurast-sdk.mjs    # programmatic deploy (CI/ops, не TEE)
├── .github/workflows/
│   ├── ci.yml
│   ├── deploy-canary.yml
│   ├── validate-relay-secrets.yml
│   ├── provision-relay-infra.yml
│   └── deploy-relay.yml
├── infra/selectel/                 # Terraform + cloud-init (Selectel relay VM)
├── modules/
│   ├── hello/                    # эталонный модуль (onetime)
│   ├── coordinator/              # interval, registry + scorecard (Phase 2)
│   └── module-template/          # scaffold для новых модулей
├── packages/nostr-client/        # Nostr coordination library
└── docs/                         # roadmap, map, nostr-protocol, relay-ops, github-actions, economics
```

---

## Ссылки

### Acurast — Getting Started

- [Acurast Docs (hub)](https://docs.acurast.com/)
- [Quickstart](https://docs.acurast.com/developers/getting-started/quickstart)
- [Quickstart — Cargo](https://docs.acurast.com/developers/getting-started/quickstart-cargo)
- [Quickstart — Tunnel (Canary)](https://docs.acurast.com/developers/getting-started/quickstart-tunnel)
- [Example Apps](https://docs.acurast.com/developers/getting-started/examples)
- [acurast-example-apps](https://github.com/Acurast/acurast-example-apps) (GitHub)
- [acurast-cli](https://github.com/Acurast/acurast-cli) (GitHub)

### Acurast — Build & Runtime

- [Deployment Config (`acurast.json`)](https://docs.acurast.com/developers/build/deployment-config)
- [Environment Variables](https://docs.acurast.com/developers/build/environment-variables)
- [Node.js Runtime Environment](https://docs.acurast.com/developers/build/nodejs-runtime-environment)
- [Cargo Runtime Environment](https://docs.acurast.com/developers/build/cargo-runtime-environment)
- [On-Demand Deployments](https://docs.acurast.com/developers/build/on-demand-deployments)
- [LLM on Acurast](https://docs.acurast.com/developers/build/llm-on-acurast)

### Acurast — Tools

- [CLI](https://docs.acurast.com/developers/tools/cli)
- [SDK](https://docs.acurast.com/developers/tools/sdk)
- [DevTools](https://docs.acurast.com/developers/tools/devtools)
- [Deploy Agent (x402)](https://docs.acurast.com/developers/tools/deploy-agent)

### Acurast — Processors

- [Processors (hub)](https://docs.acurast.com/processors)
- [Become a Compute Provider](https://docs.acurast.com/processors/become-compute-provider)
- [Processor Rewards](https://docs.acurast.com/processors/rewards)
- [Benchmarks](https://docs.acurast.com/processors/benchmarks)

### Acurast — Protocol & Reference

- [Node Setup](https://docs.acurast.com/acurast-protocol/node-setup)
- [Node Tunnel Setup (Canary)](https://docs.acurast.com/acurast-protocol/node-tunnel-setup)
- [Audits](https://docs.acurast.com/acurast-protocol/audits)
- [Canary → Mainnet](https://docs.acurast.com/acurast-protocol/from-canary-to-mainnet/overview)
- [Architecture Overview](https://docs.acurast.com/acurast-protocol/architecture/architecture)
- [End-to-End Deployment](https://docs.acurast.com/acurast-protocol/architecture/end-to-end)
- [Application Layer](https://docs.acurast.com/acurast-protocol/architecture/application-layer)
- [Execution Layer](https://docs.acurast.com/acurast-protocol/architecture/execution-layer)
- [Consensus Layer](https://docs.acurast.com/acurast-protocol/architecture/consensus-layer)
- [Network Instances](https://docs.acurast.com/acurast-protocol/architecture/instances)
- [Matcher](https://docs.acurast.com/acurast-protocol/architecture/architecture#matcher)

### Nostr & прочее

- [Nostr NIPs](https://github.com/nostr-protocol/nips)

