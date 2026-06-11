# GitHub Actions — текущее состояние и планы

## Что уже есть

Workflow [`.github/workflows/ci.yml`](../.github/workflows/ci.yml):

```
checkout → docker compose build → install → test → bundle → smoke run
```

Это **тот же путь**, что `./scripts/dev` локально — CI и dev не расходятся.

## Что учесть сейчас (до расширения CI)

### 1. Единый Docker-путь

Все проверки — через `docker compose run --rm dev`. Не добавлять параллельный «npm на ubuntu-latest» без веской причины: иначе Cloud Agents, локальная среда и CI начнут расходиться.

### 2. Имена jobs и Bugbot / Cursor

- Основной job: **`verify`** — стабильное имя для Bugbot Autofix и Automations («CI completed»).
- Check name в PR будет `CI / verify` (или как назовёте workflow `name:`).

### 3. Секреты — только через GitHub Secrets

| Secret | Когда добавлять | Где использовать |
|--------|-----------------|------------------|
| `ACURAST_MNEMONIC_HELLO` | Deploy `hello` из Actions | Environment **canary** |
| `ACURAST_MNEMONIC_COORDINATOR` | Deploy `coordinator` | Environment **canary** |
| `ACURAST_MNEMONIC` | Fallback, если нет per-module secret | Environment **canary** |
| `CURSOR_API_KEY` | Cursor CLI в Actions | Будущий workflow для авто-фиксов/docs |
| `RELAY_URL` | Nostr relay (`wss://nostr.<ваш-домен>`) для deploy env vars | Environment **canary** (нужен для exit criteria Phase 2); хостинг и чеклист — [relay-ops.md](relay-ops.md) |

**Не коммитить** секреты. `.env` в `.gitignore`.

### 4. Deploy canary из GitHub Actions

Workflow [`.github/workflows/deploy-canary.yml`](../.github/workflows/deploy-canary.yml) — **только `workflow_dispatch`**, не на каждый PR.

**Настройка (один раз):**

1. GitHub → **Settings → Environments** → создать `canary` (опционально: required reviewers).
2. В environment **canary** добавить secrets:
   - `ACURAST_MNEMONIC_HELLO` — mnemonic из `modules/hello/.env`
   - `ACURAST_MNEMONIC_COORDINATOR` — mnemonic из `modules/coordinator/.env`
   - `RELAY_URL` — `wss://nostr.<ваш-домен>` (собственный Nostr relay; не Acurast P2P/RPC — см. [nostr-protocol.md](nostr-protocol.md#nostr-relay-на-canary-ops))
3. Actions → **Deploy Canary** → Run workflow:
   - `hello` — ✅ уже задеплоен (canary)
   - `coordinator` — следующий шаг (`dry_run: true`, затем deploy)
4. После deploy: `acurast devtools <deployment-id>` или Hub → логи execution.

Пополнение cACU: [faucet.acurast.com](https://faucet.acurast.com). Адрес кошелька:

```bash
docker compose run --rm --entrypoint bash dev -c "node scripts/show-acurast-address.mjs modules/hello"
```

Programmatic SDK (вне TEE): `scripts/deploy-acurast-sdk.mjs` — тот же стек, что `acurast deploy`.

`acurast deploy` в PR/push по-прежнему **не** запускается автоматически.

### 5. Кэширование (следующий шаг)

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

- [x] Required status checks: **`verify (hello)`**, **`verify (module-template)`**, **`verify-new-module-script`**
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
| `validate-relay-secrets.yml` | `workflow_dispatch` (`provision` \| `deploy` \| `all`) | Формат + live-проверки секретов **relay** (Keystone, S3, SSH keys, X-Token; deploy: SSH to VM) ✅ |
| `provision-relay-infra.yml` | `workflow_dispatch` (`plan` \| `apply` \| `destroy`) | Terraform: Selectel VM, сеть, floating IP, cloud-init; PTR через `X-Token` ✅ |
| `deploy-relay.yml` | `workflow_dispatch` (`deploy` \| `smoke`) | SSH → `infra/nostr-relay/` compose |

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
| `SELECTEL_STATIC_TOKEN` | PTR-шаг | `X-Token` из **Профиль → API-ключи** (не сервисный user) |
| `RELAY_HOSTNAME` | PTR/DNS/deploy | `nostr.<домен>` |
| `RELAY_SSH_HOST`, `RELAY_SSH_USER` | deploy-relay | IP и `deploy` (host можно брать из TF output) |

**Файрвол:** SG `0.0.0.0/0:22` (key-only) + `0.0.0.0/0:443`. Подробнее: [relay-ops.md — файрвол VM](relay-ops.md#файрвол-vm-canary-ssh-key-only-https-public).

**Аутентификация:** OpenStack/Terraform — пароль сервисного пользователя; PTR — `X-Token`. См. [authorization](https://docs.selectel.ru/api/authorization/).

После smoke: `RELAY_URL` в environment **canary** → `Deploy Canary` для hello/coordinator.

### 10. Provision relay VM (Selectel)

Workflow [`.github/workflows/provision-relay-infra.yml`](../.github/workflows/provision-relay-infra.yml) — environment **relay**.

1. **Validate Relay Secrets** → `provision` (зелёный).
2. **Provision Relay Infra** → `plan` — проверить diff (VM, сеть, floating IP, security group).
3. **Provision Relay Infra** → `apply`, `set_ptr: true` — создаёт VM + PTR.
4. Вручную: DNS **A** `RELAY_HOSTNAME` → `public_ip` из job summary.
5. Если `plan` падает на flavor — укажите `flavor_id` из панели Selectel (pool-specific).

Следующий workflow: **Deploy Relay** (ещё не реализован).

## Планируемые workflows

| Workflow | Триггер | Назначение |
|----------|---------|------------|
| `ci.yml` | push/PR → main | test + bundle + smoke ✅ |
| `deploy-canary.yml` | `workflow_dispatch` | canary deploy hello / coordinator ✅ |
| `validate-relay-secrets.yml` | `workflow_dispatch` | проверка секретов relay ✅ |
| `provision-relay-infra.yml` | `workflow_dispatch` | Selectel VM + сеть ✅ |
| `deploy-relay.yml` | `workflow_dispatch` | relay compose на VM 🔄 в разработке |
| `cursor-agent.yml` | issue comment / schedule | Cursor CLI (будущее) |

## Cursor Dashboard

Параллельно с Actions:

1. [Integrations → GitHub](https://cursor.com/dashboard/integrations) — repo `f0ff38/nhmind`
2. [Bugbot](https://cursor.com/dashboard/bugbot) — enable + rules в `.cursor/BUGBOT.md`
3. Secrets в Cursor Cloud — для Cloud Agents (не дублировать в GitHub без нужды)
