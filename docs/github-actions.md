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
| `ACURAST_MNEMONIC` | Canary deploy из CI | Отдельный `workflow_dispatch` job, **не** на каждый PR |
| `CURSOR_API_KEY` | Cursor CLI в Actions | Будущий workflow для авто-фиксов/docs |
| `RELAY_URL` | Интеграционные тесты с внешним relay | Optional override |

**Не коммитить** секреты. `.env` в `.gitignore`.

### 4. Deploy в CI — отложить

`acurast deploy` в PR/push **не рекомендуется**:

- тратит cACU/ACU;
- требует funded wallet;
- TEE-поведение не валидируется unit-тестами.

Когда понадобится — отдельный workflow:

```yaml
on:
  workflow_dispatch:
  push:
    tags: ['v*']
```

с `environment: canary` (GitHub Environments + required reviewers).

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

### 8. Branch protection (Phase 0)

На `main` (настройка в GitHub → Settings → Branches):

- [x] Required status checks: **`verify`** (matrix jobs) и **`verify-new-module-script`**
- [ ] Require pull request before merging
- [ ] Do not allow bypassing the above settings
- optional: Bugbot `Cursor Bugbot`

Через CLI (нужны admin-права на репо):

```bash
gh api repos/f0ff38/nhmind/branches/main/protection -X PUT \
  -H "Accept: application/vnd.github+json" \
  -f required_status_checks='{"strict":true,"checks":[{"context":"verify"},{"context":"verify-new-module-script"}]}' \
  -f enforce_admins=false \
  -f required_pull_request_reviews='{"required_approving_review_count":0}' \
  -f restrictions=null
```

> Если API недоступен — включите те же правила вручную в UI после merge Phase 0.

### 9. Артефакты bundle (опционально)

Для релизов можно публиковать `modules/*/dist/bundle.js` как artifact — не коммитить `dist/` в git (уже в `.gitignore`).

## Планируемые workflows

| Workflow | Триггер | Назначение |
|----------|---------|------------|
| `ci.yml` | push/PR → main | test + bundle + smoke ✅ |
| `deploy-canary.yml` | manual / tag | canary deploy с `ACURAST_MNEMONIC` |
| `cursor-agent.yml` | issue comment / schedule | Cursor CLI (будущее) |

## Cursor Dashboard

Параллельно с Actions:

1. [Integrations → GitHub](https://cursor.com/dashboard/integrations) — repo `f0ff38/nhmind`
2. [Bugbot](https://cursor.com/dashboard/bugbot) — enable + rules в `.cursor/BUGBOT.md`
3. Secrets в Cursor Cloud — для Cloud Agents (не дублировать в GitHub без нужды)
