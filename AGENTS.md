# AGENTS.md — инструкции для Cursor (Cloud Agents, Automations, CLI)

**Точка входа — [README.md](README.md)** (корень проекта). Затем [docs/roadmap.md](docs/roadmap.md) (фаза и checkpoint). Навигация по всем docs — [docs/map.md](docs/map.md).

При добавлении или изменении документации **обязательно** обновляйте [docs/map.md](docs/map.md); при смене статуса фазы — [roadmap.md](docs/roadmap.md). См. [правила в map.md](docs/map.md#правила-обновления-карты-агенты-и-pr).

## Проект

**NostrHiveMind (nhmind)** — децентрализованные AI-агенты: исполнение в TEE на [Acurast](https://docs.acurast.com/), координация через [Nostr](https://github.com/nostr-protocol/nips).

## Структура

```
modules/hello/          # стартовый Acurast deployment (TypeScript → dist/bundle.js)
modules/coordinator/    # interval coordinator (Phase 2)
packages/nostr-client/  # Nostr coordination library
infra/selectel/         # Selectel relay VM (Terraform + cloud-init)
scripts/dev             # Docker-обёртка (основной dev/CI путь)
.cursor/                # Cloud Agent environment + Bugbot rules
.github/workflows/      # CI, canary deploy, relay validate/provision
```

Новые business-модули — в `modules/<name>/`, каждый со своим `acurast.json`.

**Текущая фаза:** Phase 2 (Coordinator + relay на Selectel) — см. [docs/roadmap.md](docs/roadmap.md) (таблица статуса и **checkpoint — следующая сессия**). Phase 0–1 завершены.

Новый модуль: `./scripts/new-module.sh <name>` → `NHIND_MODULE_DIR=modules/<name> ./scripts/dev test`

## Обязательные проверки перед PR

Используйте тот же путь, что и CI: **только Docker/container**, без host Node/npm на локальном ПК пользователя.

```bash
./scripts/dev install
./scripts/dev test
./scripts/dev bundle
./scripts/dev run
```

Если Docker daemon недоступен локально — **не** запускать host fallback; зафиксируйте, что проверки не выполнены. Простые проверки можно запускать через локальный Docker пользователя. Проверки, которым нужен сетевой доступ к Selectel/GitHub Environments, выполнять только через GitHub Actions + Selectel, а не с локального ПК.

Сетевые/ops проверки:

```bash
# local container-only checks
docker compose -f infra/nostr-relay/docker-compose.yml config
docker compose run --rm dev node --check infra/nostr-relay/http-bridge/server.mjs

# networked checks: run via GitHub Actions environment relay/canary
# Validate Relay Secrets / Provision Relay Infra / Deploy Relay / Relay Uptime / Deploy Canary
```

## Архитектурные правила

1. **Deployments, не «recipes»** — каждый модуль: bundle → `acurast.json` → `acurast deploy`.
2. **Node.js v20** — target runtime Acurast processors.
3. **Один bundle** — `dist/bundle.js`, зависимости внутри, без тяжёлых native-модулей.
4. **Секреты** — только `.env` локально + GitHub Environments для ops/deploy + `includeEnvironmentVariables`; **никогда** в коде или bundle.
5. **Подпись** — `_STD_.signers` в TEE; локально — mock из `modules/hello/src/runtime/local-std.ts`.
6. **Nostr** — NIP-90 (jobs), NIP-44 (шифрование), NIP-33 (replaceable state); не использовать Nostr как БД. На Acurast processor: relay через `httpGET`/`httpPOST` (`@nhmind/nostr-client` HTTP backend), **не** npm `ws` и **не** `_STD_.ws` (это P2P mesh, не Nostr relay). Подпись: `createAcurastSigner(_STD_)`.
7. **Гибридная координация** — Nostr (`RELAY_URL`, собственный relay на домене оператора) для публичного state/jobs; `_STD_.ws` — внутренний hot path (Phase 3+). Acurast P2P/tunnel relays и Substrate RPC **не** являются `RELAY_URL`. См. [docs/nostr-protocol.md](docs/nostr-protocol.md), ops relay: [docs/relay-ops.md](docs/relay-ops.md).
8. **Mainnet defaults** — `onlyAttestedDevices: true`, `mutability: Immutable` (в dev/canary-модулях допустим `Mutable`).

## Что агенты НЕ делают автоматически

| Действие | Почему |
|----------|--------|
| `acurast live` | Нужен физический processor (телефон) |
| Canary/mainnet deploy | Нужен `ACURAST_MNEMONIC` и cACU/ACU |
| TEE / реальные `_STD_.signers` | Только на Acurast processor |
| DNS TXT `_acu.<host>` whitelist | Нужны реальные DNS-записи владельца домена |

Если задача требует deploy — опишите шаги для человека; не коммитьте mnemonic.

## Секреты проекта

Все deploy/ops секреты проекта хранятся только в GitHub Environments: <https://github.com/f0ff38/nhmind/settings/environments>. Не переносить их в repository secrets, Cursor secrets, файлы `.env`, Terraform state или docs.

Environment **canary**:

| Secret | Назначение |
|--------|------------|
| `ACURAST_MNEMONIC_COORDINATOR` | Deploy/inspect `modules/coordinator` |
| `ACURAST_MNEMONIC_HELLO` | Deploy/inspect `modules/hello` |
| `RELAY_HOSTNAME` | FQDN relay; workflow собирает `RELAY_URL=wss://<host>/` |
| `ACURAST_EXAMPLE_WEBHOOK_URL` | Опционально: report endpoint для `deploy-acurast-example-smoke.yml` |

Environment **mainnet**:

| Secret | Назначение |
|--------|------------|
| `ACURAST_MNEMONIC_MAINNET` | Единый deploy/payment wallet для mainnet smoke/deploy workflows |
| `ACURAST_EXAMPLE_WEBHOOK_URL` | Опционально: breadcrumb/report endpoint для `deploy-acurast-example-smoke-mainnet.yml` |

Environment **relay**:

| Secret | Назначение |
|--------|------------|
| `RELAY_DEPLOY_SSH_PRIVATE_KEY` | SSH deploy на relay VM |
| `RELAY_DEPLOY_SSH_PUBLIC_KEY` | SSH keypair для Terraform/cloud-init |
| `RELAY_HOSTNAME` | FQDN relay для DNS/PTR/TLS/deploy |
| `SELECTEL_ACCOUNT_ID` | Selectel account number |
| `SELECTEL_AVAILABILITY_ZONE` | AZ для VM, например `ru-3a` |
| `SELECTEL_PROJECT_ID` | Selectel cloud project id |
| `SELECTEL_SERVICE_PASSWORD` | Service user password |
| `SELECTEL_SERVICE_USER` | Service user name |
| `SELECTEL_STATIC_TOKEN` | Selectel IPAM/PTR `X-Token` |
| `TF_STATE_S3_ACCESS_KEY` | Terraform state S3 access key |
| `TF_STATE_S3_BUCKET` | Terraform state S3 bucket |
| `TF_STATE_S3_SECRET_KEY` | Terraform state S3 secret key |

Опциональные secrets (`SELECTEL_REGION`, `TF_STATE_S3_REGION`, `RELAY_DNS_ZONE`, `RELAY_DNS_ZONE_ID`, `SELECTEL_IAM_PROJECT_NAME`, `RELAY_TLS_KNOX_CERT_ID`) добавлять только если workflow явно требует override; не считать их обязательными defaults.

## Ветки и PR

- Feature-ветки: `cursor/<описание>-<suffix>` или `feat/<описание>`.
- Base branch: `main`.
- Минимальный diff; не рефакторить несвязанный код.
- Обновляйте тесты при изменении логики модулей.

### Git: как запускать и от чьего имени

- Все git-команды запускать **из корня репозитория** (`C:\Users\716\Documents\nhmind` на Windows; `/workspace` или checkout root в контейнере/CI). Перед операциями всегда проверять `git status --short --branch`.
- На Windows для git-команд с Bash-синтаксисом (`heredoc`, `&&`, shell quoting) использовать **Git Bash**: `C:\Program Files\Git\bin\bash.exe`. В PowerShell использовать `;` вместо `&&` и временные файлы вместо heredoc.
- Агентам **запрещено менять git config** (`git config --global` / локальный config). Если git требует author identity, задавать ее только на одну команду через env vars.
- Author/committer для агентских коммитов в этом репозитории: `Igor Kolesnikov <51603602+f0ff38@users.noreply.github.com>` через `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL`.
- Коммиты создавать только по явному запросу пользователя. Сообщение коммита передавать через file/heredoc, не через интерактивный editor; при rebase использовать `GIT_EDITOR=true`, если нужно сохранить существующее сообщение.
- Перед PR: `git fetch origin`, feature branch должен быть поверх `origin/main`; при конфликтах сохранять изменения `main` и переносить refactor поверх них. После push создавать PR через `gh pr create`, checks смотреть через `gh pr checks <number> --watch`.
- Не использовать destructive git commands (`reset --hard`, `checkout --`, force push) без отдельного явного разрешения пользователя.

## Cursor Cloud specific instructions

Cloud Agent VM: Ubuntu, конфигурация в [.cursor/environment.json](.cursor/environment.json).

### Setup (idempotent)

```bash
npm ci --prefix packages/nostr-client
npm run build --prefix packages/nostr-client
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

### Секреты

Deploy/ops secrets — только GitHub Environments `canary` и `relay` (см. раздел выше). Cursor Dashboard secrets не являются source of truth для этого проекта; не дублировать туда mnemonics/Selectel credentials без отдельной явной задачи.

## GitHub Actions

CI: [.github/workflows/ci.yml](.github/workflows/ci.yml) — `install → test → bundle → smoke run` в Docker.

Relay (environment **relay**): [validate-relay-secrets.yml](.github/workflows/validate-relay-secrets.yml), [provision-relay-infra.yml](.github/workflows/provision-relay-infra.yml), [deploy-relay.yml](.github/workflows/deploy-relay.yml), [relay-uptime.yml](.github/workflows/relay-uptime.yml). Canary (environment **canary**): [deploy-canary.yml](.github/workflows/deploy-canary.yml), inspect workflows. Mainnet smoke (environment **mainnet**): [deploy-acurast-example-smoke-mainnet.yml](.github/workflows/deploy-acurast-example-smoke-mainnet.yml), только `workflow_dispatch`. Ops: [docs/relay-ops.md](docs/relay-ops.md).

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
