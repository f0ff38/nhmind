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
| `RELAY_URL` | Nostr relay (`wss://nostr.<ваш-домен>`) для deploy env vars | Environment **canary** (нужен для exit criteria Phase 2) |

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

## Планируемые workflows

| Workflow | Триггер | Назначение |
|----------|---------|------------|
| `ci.yml` | push/PR → main | test + bundle + smoke ✅ |
| `deploy-canary.yml` | `workflow_dispatch` | canary deploy hello / coordinator ✅ |
| `cursor-agent.yml` | issue comment / schedule | Cursor CLI (будущее) |

## Cursor Dashboard

Параллельно с Actions:

1. [Integrations → GitHub](https://cursor.com/dashboard/integrations) — repo `f0ff38/nhmind`
2. [Bugbot](https://cursor.com/dashboard/bugbot) — enable + rules в `.cursor/BUGBOT.md`
3. Secrets в Cursor Cloud — для Cloud Agents (не дублировать в GitHub без нужды)
