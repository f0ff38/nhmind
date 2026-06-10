# NostrHiveMind (nhmind)

Децентрализованная система AI-агентов: **исполнение в TEE на [Acurast](https://docs.acurast.com/)**, **координация через [Nostr](https://github.com/nostr-protocol/nips)**.

> Репозиторий: [github.com/f0ff38/nhmind](https://github.com/f0ff38/nhmind)

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

| Компонент | Где живёт | Назначение |
|-----------|-----------|------------|
| **Coordinator** | Acurast deployment (`interval`) | Читает Nostr, ведёт scorecard модулей, регистрирует/останавливает deployments через SDK |
| **Business module** | Отдельный Acurast deployment на модуль | Доходная логика; реализует `IBusinessModule` |
| **Nostr relays** | Публичные relays (список в конфиге) | Транспорт событий, не source of truth для финансов |

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

| Данные | Где хранятся |
|--------|--------------|
| Задачи, результаты, feedback | [NIP-90](https://github.com/nostr-protocol/nips/blob/master/90.md) (kind `5000–5999` / `6000–6999` / `7000`) |
| Статус агента, capacity, pricing | Parameterized replaceable events ([NIP-33](https://github.com/nostr-protocol/nips/blob/master/33.md)) |
| Конфиденциальные payload | [NIP-44](https://nips.nostr.com/44) |
| Scorecard, ROI, решения coordinator | События coordinator + on-chain метрики ACU/revenue |
| Секреты, ключи подписи | TEE: `_STD_.signers` + `_STD_.env` |

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

| Параметр | Рекомендация |
|----------|--------------|
| `onlyAttestedDevices` | `true` — только attested hardware |
| `mutability` | `Immutable` в production; `Mutable` только для dev и `reuseKeysFrom` |
| `network` | `canary` → после валидации `mainnet` |
| `execution.type` | `interval` для агентов; `onetime` для разовых job |
| `maxExecutionTimeInMs` | Задавать явно под worst-case сценарий модуля |
| `maxCostPerExecution` | Всегда лимитировать; оценка через `acurast estimate-fee` |
| `minProcessorReputation` | Поднимать для production-модулей |
| `processorWhitelist` | Для canary и чувствительных модулей |
| `requiredModules` | `['DataEncryption']` при работе с секретами |

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

| Этап | Инструмент |
|------|------------|
| Scaffold | `npx @acurast/cli new <module>` |
| Локальная отладка | `node dist/bundle.js`, затем `acurast live` |
| Canary | `acurast deploy` на `canary` |
| Production | `acurast deploy` на `mainnet` или [@acurast/sdk](https://docs.acurast.com/) |
| Оплата без ACU-аккаунта | [Deploy Agent](https://docs.acurast.com/developers/deploy-agent) (x402, USDC на Base) |
| LLM inference | `requiredModules` для LLM; confidential inference в TEE |

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

## Структура репозитория (целевая)

```
nhmind/
├── README.md
├── packages/
│   ├── coordinator/          # Acurast deployment + @acurast/sdk
│   ├── nostr-client/         # NIP-90, NIP-44, NIP-33 helpers
│   └── module-template/      # scaffold для нового business module
├── modules/                  # business deployments (каждый — свой acurast.json)
└── docs/
    ├── nostr-protocol.md     # kinds, tags, схемы событий
    └── economics.md          # формулы ROI, scorecard
```

---

## Команды разработки

```bash
# Новый модуль
npx @acurast/cli new modules/<name>

# Сборка bundle
npm run bundle          # → dist/bundle.js

# Локальный прогон
node dist/bundle.js

# Live-отладка на processor
acurast live

# Оценка стоимости
acurast estimate-fee

# Деплой
acurast deploy          # canary по умолчанию в acurast.json
```

---

## Ссылки

- [Acurast Docs](https://docs.acurast.com/)
- [Node.js Runtime API](https://docs.acurast.com/developers/job-runtime-environment/)
- [Deploy Agent (x402)](https://docs.acurast.com/developers/deploy-agent)
- [acurast-cli](https://github.com/Acurast/acurast-cli)
- [acurast-example-apps](https://github.com/Acurast/acurast-example-apps)
- [Nostr NIPs](https://github.com/nostr-protocol/nips)
