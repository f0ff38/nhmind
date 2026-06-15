# GitHub Actions — текущее состояние и планы

**Навигация:** [README](../README.md) · [map.md](map.md) · [roadmap.md](roadmap.md)

---

## Что уже есть

Workflow [`.github/workflows/ci.yml`](../.github/workflows/ci.yml):

```
checkout → ./scripts/dev install → ./scripts/dev test → ./scripts/dev bundle → ./scripts/dev run
```

Это **тот же wrapper contract**, что локально: CI и dev идут через Docker-only `./scripts/dev`, без npm/Node на runner host.

## Что учесть сейчас (до расширения CI)

### 1. Единый Docker-путь

Все проверки — через `./scripts/dev` (внутри он вызывает `docker compose run --rm dev`). Не добавлять параллельный «npm на ubuntu-latest» без веской причины: иначе Cloud Agents, локальная среда и CI начнут расходиться.

### 2. Имена jobs и Bugbot / Cursor

- Основной matrix job: **`verify`** — стабильное имя для Bugbot Autofix и Automations («CI completed»).
- Check names в PR: `CI / verify (hello)`, `CI / verify (coordinator)`, `CI / verify (module-template)`, `CI / verify (oracle-feed)`.
- Дополнительные обязательные checks: `CI / verify-nostr-client`, `CI / verify-new-module-script`.
- Дополнительный необязательный diagnostic check: `CI / verify-acurast-example-smoke` (official Acurast example smoke, не branch-protection required).

### 3. Секреты — только через GitHub Secrets

| Secret | Когда добавлять | Где использовать |
|--------|-----------------|------------------|
| `ACURAST_MNEMONIC_HELLO` | Deploy `hello` из Actions | Environment **canary** |
| `ACURAST_MNEMONIC_COORDINATOR` | Deploy `coordinator` | Environment **canary** |
| `ACURAST_MNEMONIC` | Fallback, если нет per-module secret | Environment **canary** |
| `ACURAST_EXAMPLE_WEBHOOK_URL` | Опциональный breadcrumb/report endpoint для official example smoke | Environment **canary** / **mainnet** |
| `ACURAST_MNEMONIC_MAINNET` | Единый deploy/payment wallet для mainnet smoke/deploy workflows | Environment **mainnet** |
| `CURSOR_API_KEY` | Cursor CLI в Actions | Будущий workflow для авто-фиксов/docs |
| `RELAY_HOSTNAME` | FQDN relay (`nostr.<домен>`); workflow собирает `RELAY_URL=wss://<host>/` | Environment **canary** (тот же hostname, что в **relay**); хостинг — [relay-ops.md](relay-ops.md) |

**Не коммитить** секреты. `.env` в `.gitignore`.

### 4. Deploy canary из GitHub Actions

Workflow [`.github/workflows/deploy-canary.yml`](../.github/workflows/deploy-canary.yml) — **только `workflow_dispatch`**, не на каждый PR.

**Настройка (один раз):**

1. GitHub → **Settings → Environments** → создать `canary` (опционально: required reviewers).
2. В environment **canary** добавить secrets:
   - `ACURAST_MNEMONIC_HELLO` — mnemonic из `modules/hello/.env`
   - `ACURAST_MNEMONIC_COORDINATOR` — mnemonic из `modules/coordinator/.env`
   - `RELAY_HOSTNAME` — `nostr.<ваш-домен>` (без схемы); `deploy-canary.yml` пишет в `.env` модульный `RELAY_URL=wss://<RELAY_HOSTNAME>/` (не Acurast P2P/RPC — см. [nostr-protocol.md](nostr-protocol.md#nostr-relay-на-canary-ops))
3. Actions → **Deploy Canary** → Run workflow (порядок и текущий блокер — **[roadmap checkpoint](roadmap.md#checkpoint--следующая-сессия)**):
   - jobs `compute-acu-txt` (environment **canary**) + `upsert-acu-txt` (environment **relay**) — **PTR ensure/verify** ([ensure-relay-ptr.sh](../infra/selectel/scripts/ensure-relay-ptr.sh), [verify-relay-ptr.sh](../infra/selectel/scripts/verify-relay-ptr.sh)) + TXT `_acu.<RELAY_HOSTNAME>` перед deploy
   - `hello` — submit/register (≤5 min, [deploy-canary-acurast.sh](../scripts/deploy-canary-acurast.sh)) + smoke `30090` (wait по schedule + 90s, preflight до 5 min)
   - **Hello relay A/B** (изоляция relay vs processor): input `relay_url_override` (напр. `wss://relay.damus.io/`) — только `module=hello`; пишет `RELAY_SKIP_WHITELIST=1` (нет `_acu` TXT у чужого relay); smoke слушает тот же host. Пусто = **operator relay** (`RELAY_HOSTNAME`); deploy всё равно на **Acurast canary**, не mainnet.
   - **Hello minimal smoke** (изоляция processor vs bundle logic): input `minimal_smoke=true` — `HELLO_MINIMAL=1` в bundle (только `hello-minimal-start` / `hello-minimal-done`, без Nostr/network); smoke `30090` пропускается; post-window SDK+CLI inspect остаётся.
   - **Hello diagnostic runtime** (точечная диагностика Acurast processor/reporting): input `diagnostic_runtime=true` — только `module=hello`; форсирует `HELLO_MINIMAL=1`, расширяет `execution.maxExecutionTimeInMs` и `maxAllowedStartDelayInMs` до 300s, поднимает `maxCostPerExecution` для одного controlled run; обычные defaults `acurast.json` не меняются.
   - `coordinator` — только после hello heartbeat на relay; smoke `30092`/`30091` — [smoke-coordinator-relay.sh](../scripts/smoke-coordinator-relay.sh)
4. **Диагностика deployments без Hub/DevTools web** (основной путь — CLI + SDK из GHA):
   - **Inspect Canary Deployment** (`inspect-canary-deployments.yml`) — `workflow_dispatch`: `module`, опционально `deployment_id` (число из Hub, напр. `378421`), опционально `deploy_run_id` (номер run **Deploy Canary** — скачивает artifact `acurast-deploy-<module>-<id>` для `acurast deployments <id>`).
   - Скрипты: [inspect-canary-deployments.sh](../scripts/inspect-canary-deployments.sh) → [fetch-acurast-deployment-status.mjs](../scripts/fetch-acurast-deployment-status.mjs) (indexer + on-chain RPC: `storedJobRegistration`, `getAcknowledgedProcessors`, `assignedProcessors`) + [inspect-canary-deployment-cli.sh](../scripts/inspect-canary-deployment-cli.sh) (`acurast deployments <id>` — полный Assignments JSON, нужен локальный `.acurast/deploy/*-<id>.json`).
   - **Deploy Canary** вызывает SDK+CLI inspect после регистрации и после execution window; публикует artifact `.acurast/deploy/`; smoke **не** зависит от DevTools API.
   - Локально:
     ```bash
     docker compose run --rm dev node scripts/fetch-acurast-deployment-status.mjs --module hello --deployment-id 378421
     bash scripts/inspect-canary-deployment-cli.sh hello 378421  # после deploy или с artifact
     ```
   - DevTools web/API (`devtools.acurast.com`, `api.devtools.acurast.com`) — **опционально**, часто 502 из GHA; см. `inspect-canary-devtools.yml` только если API доступен.

Пополнение cACU: [faucet.acurast.com](https://faucet.acurast.com). Адрес кошелька:

```bash
docker compose run --rm --entrypoint bash dev -c "node scripts/show-acurast-address.mjs modules/hello"
```

Programmatic SDK (вне TEE): `scripts/deploy-acurast-sdk.mjs` — тот же стек, что `acurast deploy`.

**GHA deploy (hello/coordinator):** [deploy-canary-acurast.sh](../scripts/deploy-canary-acurast.sh) — `timeout` после on-chain registration (не ждать processor match 30+ min). `startAt.msFromNow: 300000` в `acurast.json` — буфер для match до Start (см. [README](../README.md#acurast-обязательные-практики)).

**Official example smoke (canary):** [`.github/workflows/deploy-acurast-example-smoke.yml`](../.github/workflows/deploy-acurast-example-smoke.yml) — контрольный canary deploy `modules/acurast-example-smoke` на базе Acurast `app-benchmark-nodejs`; использует `ACURAST_MNEMONIC_HELLO`/fallback и optional `ACURAST_EXAMPLE_WEBHOOK_URL` или manual input `webhook_url`. Если `WEBHOOK_URL` задан, bundle отправляет breadcrumb telemetry (`started`, `bench-start`, `network-start`, `done`/`catch-error`) и финальный payload.

**Official example smoke (mainnet):** [`.github/workflows/deploy-acurast-example-smoke-mainnet.yml`](../.github/workflows/deploy-acurast-example-smoke-mainnet.yml) — ручной diagnostic A/B на **Acurast mainnet** для проверки canary-specific blocker. Environment **mainnet**, secret `ACURAST_MNEMONIC_MAINNET`, optional `ACURAST_EXAMPLE_WEBHOOK_URL` или manual input `webhook_url`, RPC `wss://public-rpc.mainnet.acurast.com`. Workflow `workflow_dispatch`, default `dry_run=true`; для on-chain deploy явно запускать `dry_run=false`.

`acurast deploy` в PR/push по-прежнему **не** запускается автоматически.

### 5. Кэширование (backlog, не блокер Phase 2)

Когда CI станет медленным:

```yaml
- uses: actions/cache@v4
  with:
    path: modules/hello/node_modules
    key: npm-hello-${{ hashFiles('modules/hello/package-lock.json') }}
```

Docker layer cache: `docker/build-push-action` или `docker compose build` с GHA cache — позже.

### 6. Path filters (когда вырастет monorepo)

```yaml
on:
  pull_request:
    paths:
      - 'modules/**'
      - 'packages/**'
      - 'Dockerfile'
      - 'docker-compose.yml'
      - '.github/workflows/**'
```

### 7. Cursor Automations

Триггер **CI completed** срабатывает на завершение workflow. Держите один основной CI workflow или явно фильтруйте по `workflow name` в automation prompt.

### 8. Branch protection (Phase 0) — ✅ настроено

На `main` (GitHub → Settings → Branches):

- [x] Required status checks: **`verify-nostr-client`**, **`verify (hello)`**, **`verify (coordinator)`**, **`verify (module-template)`**, **`verify (oracle-feed)`**, **`verify-new-module-script`**
- [ ] optional: `verify-acurast-example-smoke` как required check, если diagnostic module станет постоянным
- [x] Require pull request before merging
- [x] Do not allow bypassing the above settings
- [ ] optional: Bugbot `Cursor Bugbot` как required check

Прямой push в `main` заблокирован — только через PR с зелёным CI.

### 9. Артефакты bundle (опционально)

Для релизов можно публиковать `modules/*/dist/bundle.js` как artifact — не коммитить `dist/` в git (уже в `.gitignore`).

## Relay на Selectel (GitOps) — активный шаг

Два workflow, environment **relay** (отдельно от **canary**). Детали: [relay-ops.md](relay-ops.md#selectel-gitops-провижининг-relay).

| Workflow | Триггер | Назначение |
|----------|---------|------------|
| `validate-relay-secrets.yml` | `workflow_dispatch` (`provision` \| `deploy` \| `all`) | Формат + live-проверки секретов **relay** (Keystone, S3, SSH keys, X-Token; deploy: SSH to VM via TF `public_ip`) ✅ |
| `provision-relay-infra.yml` | `workflow_dispatch` (`plan` \| `apply` \| `destroy`) | Terraform: Selectel VM, сеть, floating IP, cloud-init; PTR через IPAM `ipam/v1` + `X-Token`; verify PTR propagation ✅ |
| `deploy-relay.yml` | `workflow_dispatch` (`deploy` \| `smoke` \| `all`) | Selectel LE + Knox PEM → SSH → `infra/nostr-relay/` compose; IP из Terraform state ✅ |
| `relay-uptime.yml` | `schedule` + `workflow_dispatch` (`smoke` \| `renew-tls`) | Регулярный smoke relay; опционально Knox PEM refresh + nginx reload без полного deploy |
| `deploy-acurast-example-smoke.yml` | `workflow_dispatch` | Контрольный canary deploy official Acurast `app-benchmark-nodejs` workload для изоляции processor/runtime blocker |
| `deploy-acurast-example-smoke-mainnet.yml` | `workflow_dispatch` | Контрольный mainnet deploy official example smoke; default `dry_run=true`, environment **mainnet** |
| `inspect-canary-devtools.yml` | `workflow_dispatch` | DevTools API (опционально; часто 502 из GHA) |
| `inspect-canary-deployments.yml` | `workflow_dispatch` | SDK + CLI deployment status (основной путь без Hub/DevTools web) |

**Секреты environment `relay`:**

| Secret | Когда | Назначение |
|--------|-------|------------|
| `SELECTEL_SERVICE_USER` / `SELECTEL_SERVICE_PASSWORD` | ✅ | Terraform/OpenStack ([quickstart](https://docs.selectel.ru/terraform/quickstart/)) |
| `SELECTEL_ACCOUNT_ID` | до 1-го plan | Номер аккаунта |
| `SELECTEL_PROJECT_ID` | до 1-го plan | ID из **Облачные серверы** (32 hex), не IAM → Проекты |
| `RELAY_DEPLOY_SSH_PRIVATE_KEY` / `RELAY_DEPLOY_SSH_PUBLIC_KEY` | до 1-го apply | SSH keypair → Selectel keypair + пользователь `deploy` |
| `SELECTEL_AVAILABILITY_ZONE` | до plan | AZ `ru-3a` (не пул `ru-3`) |
| `TF_STATE_S3_BUCKET`, `TF_STATE_S3_ACCESS_KEY`, `TF_STATE_S3_SECRET_KEY` | до `terraform init` | Remote state |
| `TF_STATE_S3_REGION` | опционально | Пул S3 бакета (`ru-3`); иначе из `SELECTEL_REGION` / AZ |
| `SELECTEL_STATIC_TOKEN` | PTR-шаг | `X-Token` из **Профиль → API-ключи**; IPAM API `https://api.selectel.ru/ipam/v1/` |
| `RELAY_HOSTNAME` | PTR/DNS/deploy | `nostr.<домен>` |
| `RELAY_DNS_ZONE` | опционально | Зона Selectel DNS (`example.com`), если не выводится из hostname |
| `RELAY_DNS_ZONE_ID` | если zone list API пустой | UUID из панели `.../registrar/<uuid>/` |
| `SELECTEL_IAM_PROJECT_NAME` | опционально | Override имени IAM-проекта для DNS; иначе из `SELECTEL_PROJECT_ID` |
| `RELAY_TLS_KNOX_CERT_ID` | опционально | Knox UUID LE-серта; иначе авто по `RELAY_HOSTNAME` |

Floating IP для SSH/deploy — **`terraform output public_ip`**. **A-запись** — автоматически в **Provision Relay Infra** (`set_dns_a`, default `true`).

**TLS:** deploy тянет LE из Selectel (DNS-01), private key — pull-on-deploy из Knox, не в secrets. См. [relay-ops.md — TLS](relay-ops.md#tls-selectel-certificate-manager-dns-01).

**Файрвол:** SG `0.0.0.0/0:22` (key-only) + `0.0.0.0/0:443` (**:80 закрыт**). Подробнее: [relay-ops.md — файрвол VM](relay-ops.md#файрвол-vm-canary-ssh-key-only-https-public).

**Аутентификация:** OpenStack/Terraform — пароль сервисного пользователя; PTR — `X-Token`. См. [authorization](https://docs.selectel.ru/api/authorization/).

После smoke: `RELAY_HOSTNAME` в environment **canary** → `Deploy Canary` для hello/coordinator (`RELAY_URL` собирается в workflow).

### 10. Provision relay VM (Selectel)

Workflow [`.github/workflows/provision-relay-infra.yml`](../.github/workflows/provision-relay-infra.yml) — environment **relay**.

1. **Validate Relay Secrets** → `provision` (зелёный).
2. **Provision Relay Infra** → `plan` — проверить diff (VM, сеть, floating IP, security group).
3. **Provision Relay Infra** → `apply`, `set_ptr: true`, `set_dns_a: true` — VM + PTR + DNS A.
4. **Deploy Relay** → `deploy` (после propagation DNS) или `smoke`.

Если `plan`/`apply` не находит flavor — auto-resolve через [resolve-relay-flavor.sh](../infra/selectel/scripts/resolve-relay-flavor.sh); override: input **`flavor_id`** (напр. `1003`).

Workflow **Deploy Relay**: [`.github/workflows/deploy-relay.yml`](../.github/workflows/deploy-relay.yml) — SSH на VM, IP из Terraform state, compose в `infra/nostr-relay/`.

## Планируемые workflows

| Workflow | Триггер | Назначение |
|----------|---------|------------|
| `ci.yml` | push/PR → main | test + bundle + smoke ✅ |
| `deploy-canary.yml` | `workflow_dispatch` | canary deploy hello / coordinator ✅ |
| `validate-relay-secrets.yml` | `workflow_dispatch` | проверка секретов relay ✅ |
| `provision-relay-infra.yml` | `workflow_dispatch` | Selectel VM + сеть ✅ |
| `deploy-relay.yml` | `workflow_dispatch` | relay compose на VM ✅ |
| `relay-uptime.yml` | schedule / `workflow_dispatch` | relay smoke + TLS refresh ✅ |
| `deploy-acurast-example-smoke.yml` | `workflow_dispatch` | official Acurast example smoke для processor/runtime диагностики |
| `deploy-acurast-example-smoke-mainnet.yml` | `workflow_dispatch` | mainnet A/B official example smoke для проверки canary-specific blocker |
| `inspect-canary-devtools.yml` | `workflow_dispatch` | DevTools API (опционально) |
| `inspect-canary-deployments.yml` | `workflow_dispatch` | SDK + CLI deployment diagnostics ✅ |
| `cursor-agent.yml` | issue comment / schedule | Cursor CLI (будущее) |

## Cursor Dashboard

Параллельно с Actions:

1. [Integrations → GitHub](https://cursor.com/dashboard/integrations) — repo `f0ff38/nhmind`
2. [Bugbot](https://cursor.com/dashboard/bugbot) — enable + rules в `.cursor/BUGBOT.md`
3. Secrets в Cursor Cloud — для Cloud Agents (не дублировать в GitHub без нужды)
