# Nostr protocol — NostrHiveMind

Спецификация событий координации для **NostrHiveMind (nhmind)**.

**Связанные документы:** [README](../README.md) (корень) · [map.md](map.md) · [roadmap.md](roadmap.md) · [relay-ops.md](relay-ops.md) · [economics.md](economics.md) · [AGENTS.md](../AGENTS.md)

**Статус:** Phase 1 (черновик v1). Изменения — через PR с обновлением `schema` в payload.

---

## Принципы

1. **Nostr — транспорт, не БД.** Relays не являются source of truth для treasury, ROI или финальных решений coordinator. События — сигналы с eventual consistency.
2. **Replaceable state — [NIP-33](https://github.com/nostr-protocol/nips/blob/master/33.md).** Heartbeat, scorecard и registry — parameterized replaceable events (`kind` + `d` tag).
3. **Jobs — [NIP-90](https://github.com/nostr-protocol/nips/blob/master/90.md).** Запросы `5000–5999`, результаты `6000–6999`, feedback `7000`.
4. **Шифрование — [NIP-44](https://nips.nostr.com/44).** Конфиденциальные поля job request/result; **не** NIP-04.
5. **Подпись — secp256k1.** В production — `_STD_.signers.secp256k1` на Acurast processor; локально — mock signer из `local-std.ts`.
6. **Версионирование payload.** Поле `schema` в JSON content (`nhmind/<type>/v1`).

---

## Идентификаторы

| Поле | Описание |
|------|----------|
| `module_id` | Имя модуля в репозитории (`hello`, `oracle-feed`, …). Стабильный строковый ID. |
| `deployment_id` | Объект Acurast job id: `{ "origin": { "kind", "source" }, "id": string }` — из `_STD_.job.getId()`. |
| `coordinator_id` | `module_id` coordinator deployment (`coordinator` в Phase 2). |
| `job_id` | Уникальный id job request (hex или UUID), дублируется в tag `d` (NIP-90). |
| `d` (NIP-33) | Parameterized replaceable identifier внутри kind (см. таблицы ниже). |

---

## Kind registry

### Replaceable state (NIP-33)

Kinds в диапазоне `30000–39999`. Идентичность replaceable-события: `pubkey` + `kind` + `d` tag.

| Kind | `d` tag | Publisher | Phase | Назначение |
|------|---------|-----------|-------|------------|
| `30090` | `heartbeat:<module_id>` | Business module | 1 | Liveness, health, capacity |
| `30091` | `scorecard:<module_id>` | Coordinator | 2 | ROI, verdict, окно измерений |
| `30092` | `registry:<module_id>` | Coordinator | 2 | Зарегистрированный модуль, known deployment |

Новые типы replaceable-событий добавляются новым `kind` или новым префиксом в `d` (предпочтительно новый `kind`, чтобы не смешивать фильтры).

### Jobs (NIP-90)

| Kind | Направление | Publisher | Phase | Назначение |
|------|-------------|-----------|-------|------------|
| `5900` | request | Client / caller | 1 | Generic nhmind job request |
| `6900` | result | Worker module | 1 | Generic nhmind job result |
| `7000` | feedback | Client или worker | 1 | Статус job (NIP-90, фиксированный kind) |

Специализированные job types (oracle, DVM, …) **могут** занять свой kind в `5000–5999` / `6000–6999` с тем же tag layout; `5900`/`6900` — fallback для experimental-модулей Phase 1–3.

---

## Теги (общие правила)

### Обязательные для всех nhmind-событий

| Tag | Значение |
|-----|----------|
| `client` | `nhmind` — маркер экосистемы (NIP-90 convention) |

### NIP-33 (heartbeat, scorecard, registry)

| Tag | Обязательный | Значение |
|-----|--------------|----------|
| `d` | да | См. kind registry (`heartbeat:hello`, …) |
| `module` | да | `module_id` |
| `deployment` | heartbeat, registry | JSON-stringified `deployment_id` (compact, без пробелов) |

### NIP-90 (job request `5900`)

| Tag | Обязательный | Значение |
|-----|--------------|----------|
| `d` | да | `job_id` |
| `p` | да | Hex pubkey worker / target module |
| `job_type` | да | Строка (`echo`, `oracle`, `dvm`, …) |
| `bid` | нет | Стоимость в millisats (строка), если applicable |
| `t` | нет | Доп. capability tags |

### NIP-90 (job result `6900`)

| Tag | Обязательный | Значение |
|-----|--------------|----------|
| `request` | да | `job_id` из request |
| `p` | да | Pubkey requester |
| `status` | да | `success` \| `error` \| `processing` |

### NIP-90 (feedback `7000`)

| Tag | Обязательный | Значение |
|-----|--------------|----------|
| `request` | да | `job_id` |
| `status` | да | NIP-90 status: `payment-required`, `paid`, `processing`, `error`, `success`, … |

---

## Payload schemas

Content — **UTF-8 JSON** в поле `content` события, если не указано иное (NIP-44 ciphertext — см. ниже).

### `nhmind/heartbeat/v1` (kind `30090`)

Публикует business module при каждом interval/onetime run (Phase 1: `hello`).

```json
{
  "schema": "nhmind/heartbeat/v1",
  "module_id": "hello",
  "deployment_id": {
    "origin": { "kind": "local", "source": "nhmind-dev" },
    "id": "0"
  },
  "health": {
    "ok": true,
    "details": "relay=ws://nostr-relay:8080, version=local"
  },
  "capacity": {
    "max_concurrent_jobs": 1
  },
  "app_version": "0.1.0",
  "ts": 1718000000
}
```

| Поле | Тип | Описание |
|------|-----|----------|
| `health.ok` | boolean | Результат `healthCheck()` |
| `health.details` | string? | Человекочитаемый статус |
| `capacity.max_concurrent_jobs` | number | Верхняя граница параллельных NIP-90 jobs |
| `app_version` | string | Версия bundle / модуля |
| `ts` | number | Unix seconds (дублирует `created_at` для отладки) |

### `nhmind/scorecard/v1` (kind `30091`)

Публикует coordinator. Формулы ROI — [economics.md](economics.md).

```json
{
  "schema": "nhmind/scorecard/v1",
  "module_id": "hello",
  "deployment_id": {
    "origin": { "kind": "acurast", "source": "canary" },
    "id": "42"
  },
  "window_start": 1717400000,
  "window_end": 1718006400,
  "revenue_acu": "1000000",
  "cost_acu": "800000",
  "relay_fees_acu": "0",
  "roi": 1.25,
  "verdict": "promote",
  "verdict_reason": "ROI >= 1.0, stable health",
  "ts": 1718006400
}
```

| Поле | Тип | Описание |
|------|-----|----------|
| `revenue_acu`, `cost_acu`, `relay_fees_acu` | string | Целые ACU в base units (string из-за `bigint`) |
| `roi` | number | `(revenue - cost - relay_fees) / cost` |
| `verdict` | enum | `promote` \| `pause` \| `kill` |
| `verdict_reason` | string? | Краткое обоснование |

### `nhmind/registry/v1` (kind `30092`, Phase 2)

```json
{
  "schema": "nhmind/registry/v1",
  "module_id": "hello",
  "deployment_id": { "origin": { "kind": "acurast", "source": "canary" }, "id": "42" },
  "module_pubkey": "02fcf1a928bab608989a0218831efd585d1e771669756e1033c60cff4bef6f28e5",
  "network": "canary",
  "registered_at": 1717400000,
  "status": "active"
}
```

| `status` | Значение |
|----------|----------|
| `active` | Модуль в rotation |
| `paused` | Coordinator выставил pause |
| `killed` | Deployment cleanup, только архивное событие |

### `nhmind/job-request/v1` (kind `5900`)

Публичная часть request. Чувствительный `input` — отдельно (NIP-44).

```json
{
  "schema": "nhmind/job-request/v1",
  "job_id": "a1b2c3d4e5f6",
  "job_type": "echo",
  "input_encoding": "nip44",
  "ts": 1718000000
}
```

Поле `input` **не** включается в открытый JSON. Вместо этого `content` события целиком — NIP-44 ciphertext от requester к `p` (worker), либо гибрид: JSON metadata + отдельное поле `encrypted` (реализация в `packages/nostr-client` — один выбранный формат, зафиксировать в коде).

**Рекомендуемый формат Phase 1 (простой):** если `input` не секретен — plain JSON в `content` без шифрования; если секретен — весь `content` = NIP-44 blob, metadata только в tags.

### `nhmind/job-result/v1` (kind `6900`)

```json
{
  "schema": "nhmind/job-result/v1",
  "job_id": "a1b2c3d4e5f6",
  "job_type": "echo",
  "output_encoding": "plain",
  "output": { "message": "pong" },
  "ts": 1718000060
}
```

При `output_encoding: "nip44"` поле `output` опускается; `content` — ciphertext для requester pubkey.

### `nhmind/oracle-result/v1` (oracle job output, nested in `6900`)

Pull-oracle modules publish this schema inside `nhmind/job-result/v1` → `output` when `job_type: oracle`.

```json
{
  "schema": "nhmind/oracle-result/v1",
  "job_id": "a1b2c3d4e5f6",
  "feed_id": "btc-usd",
  "value": "67234.12",
  "source_fetched_at": 1718000060,
  "sources_used": 2,
  "module_id": "oracle-feed",
  "module_pubkey": "<worker-pubkey-hex>",
  "settled_msats": "100",
  "attestation": {
    "processor": "<acurast-device-address>",
    "signature": "<secp256k1-signature-hex>"
  },
  "ts": 1718000060
}
```

| Поле | Тип | Описание |
|------|-----|----------|
| `feed_id` | string | Supported feed (`btc-usd`, `eth-usd`, …) |
| `value` | string | Median price (2 decimal places) |
| `sources_used` | number | Successful API responses (≥ `ORACLE_MIN_SOURCES`) |
| `settled_msats` | string | Job bid settled for this execution |
| `attestation.signature` | string | `_STD_.signers.secp256k1.sign(hex(JSON canonical payload))` over all fields **except** `attestation` |

Canonical signed payload (UTF-8 JSON, stable key order as emitted by worker):

```json
{
  "schema": "nhmind/oracle-result/v1",
  "job_id": "...",
  "feed_id": "...",
  "value": "...",
  "source_fetched_at": 1718000060,
  "sources_used": 2,
  "module_id": "oracle-feed",
  "module_pubkey": "...",
  "settled_msats": "...",
  "ts": 1718000060
}
```

### `nhmind/job-feedback/v1` (kind `7000`)

```json
{
  "schema": "nhmind/job-feedback/v1",
  "job_id": "a1b2c3d4e5f6",
  "message": "processing"
}
```

Tag `status` дублирует машиночитаемый статус NIP-90; `message` — опциональное пояснение.

---

## NIP-44 (шифрование)

| Сценарий | От | Кому |
|----------|-----|------|
| Job input | Requester | Worker (`p` tag) |
| Job output | Worker | Requester (`p` tag на result) |

- Алгоритм: [NIP-44 v2](https://nips.nostr.com/44).
- **Запрещено:** NIP-04.
- Ключи: secp256k1 deployment keys; в dev — mock keys из `createLocalStd()`.

---

## Acurast runtime (transport и подпись)

См. [Node.js Runtime Environment](https://docs.acurast.com/developers/job-runtime-environment/).

### `_STD_.ws` ≠ WebSocket к Nostr relay

`_STD_.ws` — **P2P-сервис Acurast** (шифрованные сообщения между deployment keys: `open` / `send(recipient, payloadHex)` / `registerPayloadHandler`). Это **не** RFC6455-клиент к внешним `ws://` / `wss://` relays.

`nostr-tools` `SimplePool` ожидает обычный Nostr relay WebSocket (`REQ` / `EVENT`). Подставить `_STD_.ws` вместо npm `ws` **нельзя** без отдельного протокольного моста.

| Среда | Транспорт к Nostr relay | Пакет `ws` в bundle |
|-------|-------------------------|---------------------|
| Docker / локальный dev | `ws` (optional, dynamic require) | нет |
| Acurast processor | `httpGET` / `httpPOST` → `packages/nostr-client` HTTP backend | нет |

### Исходящая сеть на processor

- HTTP: top-level `httpGET` / `httpPOST` (callback API).
- Whitelist: `_STD_.network.whitelist(host)` + DNS TXT `_acu.<host>` ([документация](https://docs.acurast.com/developers/job-runtime-environment/#network)).
- В `acurast.json`: `usageLimit.maxNetworkRequests` > 0 для publish/subscribe.
- Не полагаться на `fetch` в production bundle без явной необходимости.

### Подпись событий

На processor: `createAcurastSigner(_STD_)` → `_STD_.signers.secp256k1.sign(eventIdHex)` (id из `getEventHash`, см. `packages/nostr-client`).

### Гибридная координация (Nostr + Acurast mesh)

Решение проекта — **два канала**, не замена одного другим:

| Слой | API | Назначение | Фаза |
|------|-----|------------|------|
| **Публичный** | Nostr relay (`RELAY_URL`) | Heartbeat/scorecard/registry (NIP-33), jobs (NIP-90), мониторинг вне TEE | Phase 1–2 (реализовано) |
| **Внутренний** | `_STD_.ws` | Команды coordinator → module, ack, срочный `pause`/`kill` | Phase 3+ (запланировано) |

Payload-контракты (`nhmind/heartbeat/v1`, `nhmind/scorecard/v1`, …) **общие** для обоих транспортов; отличается только упаковка (signed Nostr event vs hex payload в `_STD_.ws.send`).

**Не путать с Nostr relay:**

| Endpoint | Протокол | Роль в nhmind |
|----------|----------|---------------|
| `wss://nostr.<ваш-домен>` (`RELAY_URL`) | Nostr (NIP-01) | Публичная шина координации |
| `wss://websocket-proxy-*.prod.gke.acurast.com` | Acurast `_STD_.ws` | Mesh между deployment keys |
| `relay-*.canary.acurast.com:443` | Acurast P2P/tunnel relay | NAT traversal, **не** Nostr |
| `wss://public-rpc.canary.acurast.com` | Substrate RPC | Deploy, баланс, **не** Nostr |

### Nostr relay на canary (ops)

Processor ходит на relay через **HTTPS** (`wss://` → `https://` в `acurast-http` backend). Нужно:

1. **Сервер** — `nostr-rs-relay` (как в compose) за reverse proxy (Caddy/nginx) на **443**.
2. **DNS** — `A`/`AAAA` поддомена → публичный IP VPS; **PTR** того же IP → тот же hostname (для whitelist).
3. **TXT** — `_acu.<host>` = `v=base64(sha256(deployment_source ‖ host))` для каждого deploy-кошелька ([дока Acurast](https://docs.acurast.com/developers/job-runtime-environment/#network)); `deployment_source` — Account ID из `scripts/show-acurast-address.mjs`.
4. **Deploy** — `RELAY_HOSTNAME` в GitHub environment **canary** → [deploy-canary.yml](../.github/workflows/deploy-canary.yml) пишет `RELAY_URL=wss://<host>/` в `.env` модуля.

Локально: `ws://nostr-relay:8080` (compose profile `relay`, host port `7777`).

Полный чеклист хостинга, безопасность и уроки из Nosflare: [relay-ops.md](relay-ops.md).

### `_STD_.ws` в проекте

Реализация mesh — **Phase 3+** (после закрытия Phase 2 на Nostr). Не подставлять `_STD_.ws` вместо Nostr relay в `nostr-client`.

---

## Примеры событий (unsigned)

Подпись: schnorr secp256k1 (NIP-01). `id` и `sig` вычисляются клиентом при publish.

### Heartbeat

```json
{
  "kind": 30090,
  "created_at": 1718000000,
  "tags": [
    ["client", "nhmind"],
    ["d", "heartbeat:hello"],
    ["module", "hello"],
    ["deployment", "{\"origin\":{\"kind\":\"local\",\"source\":\"nhmind-dev\"},\"id\":\"0\"}"]
  ],
  "content": "{\"schema\":\"nhmind/heartbeat/v1\",\"module_id\":\"hello\",\"deployment_id\":{\"origin\":{\"kind\":\"local\",\"source\":\"nhmind-dev\"},\"id\":\"0\"},\"health\":{\"ok\":true,\"details\":\"relay=ws://nostr-relay:8080\"},\"capacity\":{\"max_concurrent_jobs\":1},\"app_version\":\"0.1.0\",\"ts\":1718000000}",
  "pubkey": "02fcf1a928bab608989a0218831efd585d1e771669756e1033c60cff4bef6f28e5"
}
```

### Job request (plain input)

```json
{
  "kind": 5900,
  "created_at": 1718000000,
  "tags": [
    ["client", "nhmind"],
    ["d", "a1b2c3d4e5f6"],
    ["p", "03aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
    ["job_type", "echo"]
  ],
  "content": "{\"schema\":\"nhmind/job-request/v1\",\"job_id\":\"a1b2c3d4e5f6\",\"job_type\":\"echo\",\"input_encoding\":\"plain\",\"input\":{\"message\":\"ping\"},\"ts\":1718000000}",
  "pubkey": "02bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
}
```

### Scorecard

```json
{
  "kind": 30091,
  "created_at": 1718006400,
  "tags": [
    ["client", "nhmind"],
    ["d", "scorecard:hello"],
    ["module", "hello"]
  ],
  "content": "{\"schema\":\"nhmind/scorecard/v1\",\"module_id\":\"hello\",\"deployment_id\":{\"origin\":{\"kind\":\"acurast\",\"source\":\"canary\"},\"id\":\"42\"},\"window_start\":1717400000,\"window_end\":1718006400,\"revenue_acu\":\"1000000\",\"cost_acu\":\"800000\",\"relay_fees_acu\":\"0\",\"roi\":1.25,\"verdict\":\"promote\",\"ts\":1718006400}",
  "pubkey": "02cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
}
```

---

## Подписки (filters)

Локальная разработка: `RELAY_URL=ws://nostr-relay:8080` (compose profile `relay`, host port `7777`).

### Coordinator слушает

```json
{ "kinds": [30090], "#client": ["nhmind"], "#module": ["hello"] }
{ "kinds": [5900], "#client": ["nhmind"], "#job_type": ["echo"] }
```

### Module слушает

```json
{ "kinds": [5900], "#client": ["nhmind"], "#p": ["<module-pubkey>"] }
{ "kinds": [30091], "#client": ["nhmind"], "#module": ["hello"] }
```

### Client слушает results

```json
{ "kinds": [6900, 7000], "#client": ["nhmind"], "#request": ["<job_id>"] }
```

---

## Разрешение конфликтов

### Replaceable (NIP-33)

Для одной тройки `(pubkey, kind, d)` на relay остаётся **последнее** событие по правилам NIP-33 (больше `created_at`, при равенстве — больше `id` как hex).

### Между relays (eventual consistency)

Coordinator и модули **не** полагаются на один relay:

1. Подписка на список relays из конфига (Phase 5: публичный список + fallback).
2. Для replaceable-событий: выбирается событие с **максимальным `created_at`** при одинаковом `(pubkey, kind, d)`.
3. Tie-break: лексикографически больший `id`.
4. Scorecard и registry: **authoritative pubkey** — coordinator deployment key.
5. Heartbeat: authoritative pubkey — **сам модуль** (его deployment key).

Nostr **не** используется для атомарных финансовых транзакций; ROI подтверждается on-chain / deployment metrics ([economics.md](economics.md)).

---

## Роли и доверие

| Событие | Кто подписывает | Кто потребляет |
|---------|-----------------|----------------|
| Heartbeat `30090` | Business module | Coordinator, мониторинг |
| Scorecard `30091` | Coordinator | Operators, autoscaling (Phase 4) |
| Registry `30092` | Coordinator | Coordinator, operators |
| Job request `5900` | Client | Worker modules |
| Job result `6900` | Worker | Client |
| Feedback `7000` | Client или worker | Обе стороны |

Проверка: подпись NIP-01 + ожидаемый `pubkey` (из registry или out-of-band deployment metadata).

---

## Локальная разработка

```bash
./scripts/dev up          # dev + nostr-relay
./scripts/dev install
./scripts/dev test
```

Relay в compose: `scsibug/nostr-rs-relay:0.10.0`, внутри сети `ws://nostr-relay:8080`.

Интеграционные тесты Phase 1 (planned):

1. Publish heartbeat `30090` с mock signer.
2. Subscribe `#module=hello`, получить то же событие.
3. Replace: второй heartbeat с тем же `d` перезаписывает первый на relay.

---

## Эволюция схемы

| Изменение | Действие |
|-----------|----------|
| Новое опциональное поле | Тот же `schema` v1, consumers игнорируют неизвестные поля |
| Breaking change | Новый `schema` (`v2`), поддержка v1 в reader до Phase N |
| Новый kind | PR в этот документ + `packages/nostr-client` + roadmap checkbox |

---

## Чеклист реализации (Phase 1)

- [x] `packages/nostr-client` — publish/subscribe, NIP-44, builders `30090` / `5900` / `6900` / `7000`
- [x] Integration tests против `nostr-relay`
- [x] `hello` публикует `30090` heartbeat при `main()`

После закрытия — отметить deliverable в [roadmap.md](roadmap.md).
