# AGENTS.md — инструкции для Cursor (Cloud Agents, Automations, CLI)

Стартовая точка для агентов. Человекочитаемый обзор — [README.md](README.md). План работ — [docs/roadmap.md](docs/roadmap.md).

## Проект

**NostrHiveMind (nhmind)** — децентрализованные AI-агенты: исполнение в TEE на [Acurast](https://docs.acurast.com/), координация через [Nostr](https://github.com/nostr-protocol/nips).

## Структура

```
modules/hello/          # стартовый Acurast deployment (TypeScript → dist/bundle.js)
scripts/dev             # Docker-обёртка (основной dev/CI путь)
.cursor/                # Cloud Agent environment + Bugbot rules
.github/workflows/      # GitHub Actions CI
```

Новые business-модули — в `modules/<name>/`, каждый со своим `acurast.json`.

**Текущая фаза:** Phase 0 (Foundation) — см. roadmap. Не начинать Phase 2+ без закрытия зависимостей.

## Обязательные проверки перед PR

Используйте тот же путь, что и CI:

```bash
./scripts/dev install
./scripts/dev test
./scripts/dev bundle
./scripts/dev run
```

Если Docker недоступен (fallback):

```bash
npm ci --prefix modules/hello
npm test --prefix modules/hello
npm run bundle --prefix modules/hello
npm run start:local --prefix modules/hello
```

## Архитектурные правила

1. **Deployments, не «recipes»** — каждый модуль: bundle → `acurast.json` → `acurast deploy`.
2. **Node.js v20** — target runtime Acurast processors.
3. **Один bundle** — `dist/bundle.js`, зависимости внутри, без тяжёлых native-модулей.
4. **Секреты** — только `.env` + `includeEnvironmentVariables`; **никогда** в коде или bundle.
5. **Подпись** — `_STD_.signers` в TEE; локально — mock из `modules/hello/src/runtime/local-std.ts`.
6. **Nostr** — NIP-90 (jobs), NIP-44 (шифрование), NIP-33 (replaceable state); не использовать Nostr как БД.
7. **Production defaults** — `onlyAttestedDevices: true`, `mutability: Immutable` (в dev-модулях допустим `Mutable`).

## Что агенты НЕ делают автоматически

| Действие | Почему |
|----------|--------|
| `acurast live` | Нужен физический processor (телефон) |
| Canary/mainnet deploy | Нужен `ACURAST_MNEMONIC` и cACU/ACU |
| TEE / реальные `_STD_.signers` | Только на Acurast processor |
| DNS TXT `_acu.<host>` whitelist | Нужны реальные DNS-записи владельца домена |

Если задача требует deploy — опишите шаги для человека; не коммитьте mnemonic.

## Ветки и PR

- Feature-ветки: `cursor/<описание>-<suffix>` или `feat/<описание>`.
- Base branch: `main`.
- Минимальный diff; не рефакторить несвязанный код.
- Обновляйте тесты при изменении логики модулей.

## Cursor Cloud specific instructions

Cloud Agent VM: Ubuntu, конфигурация в [.cursor/environment.json](.cursor/environment.json).

### Setup (idempotent)

```bash
npm ci --prefix modules/hello
```

### Verify

```bash
npm test --prefix modules/hello
npm run bundle --prefix modules/hello
npm run start:local --prefix modules/hello
```

### С Docker (если daemon доступен на VM)

```bash
docker compose build dev
./scripts/dev test
./scripts/dev bundle
```

### Секреты (Cursor Dashboard → Secrets, не в git)

| Secret | Назначение |
|--------|------------|
| `ACURAST_MNEMONIC` | Только если явно нужен canary deploy (редко) |
| `RELAY_URL` | Override relay URL для интеграционных тестов |

Секреты **не** дублировать в `.env` в коммитах.

## GitHub Actions

CI: [.github/workflows/ci.yml](.github/workflows/ci.yml) — `install → test → bundle → smoke run` в Docker.

При добавлении workflows:

- Используйте `./scripts/dev` или `docker compose run --rm dev` — parity с локальной средой.
- Job name `verify` — для интеграции с Bugbot autofix.
- Секреты deploy — только `workflow_dispatch` / protected environments, не на каждый PR.
- Будущий `CURSOR_API_KEY` — отдельный secret для Cursor CLI в Actions.

Подробнее: [docs/github-actions.md](docs/github-actions.md).

## Ссылки

- [Acurast First App Deployment](https://docs.acurast.com/developers/deploy-first-app)
- [Node.js Runtime API](https://docs.acurast.com/developers/job-runtime-environment/)
- [Cursor Cloud Agent Setup](https://cursor.com/docs/cloud-agent/setup)
- [Cursor Bugbot](https://cursor.com/docs/bugbot)
