# module-template

Эталонный scaffold для новых Acurast-модулей. **Не деплоить как production-модуль** — используйте как источник копирования.

## Создать новый модуль

```bash
./scripts/new-module.sh my-module
NHIND_MODULE_DIR=modules/my-module ./scripts/dev install
NHIND_MODULE_DIR=modules/my-module ./scripts/dev test
```

Или из контейнера:

```bash
./scripts/dev new-module my-module
```

## После копирования

1. Реализуйте бизнес-логику в `src/app.ts`
2. Настройте `acurast.json` (duration, interval, limits)
3. `./scripts/dev acurast init` в каталоге модуля (если нужен новый `.env`)
4. Canary deploy: `./scripts/dev acurast deploy` с `NHIND_MODULE_DIR=modules/my-module`
