# Карта документации — NostrHiveMind

Единый указатель по документам репозитория. **Иерархия истины:**

```
README.md          ← корень: обзор, архитектура, dev, ссылки
    └── AGENTS.md  ← агенты: правила, проверки, PR (после README)
            └── roadmap.md ← план фаз, статус, checkpoint «следующая сессия»
                    └── …  ← map.md и специализированные docs
```

**Агентам и людям:** [README.md](../README.md) → [AGENTS.md](../AGENTS.md) → [roadmap.md](roadmap.md). Остальное — по задаче, через эту карту.

---

## Уровень 0 — корень репозитория

| Документ | Назначение | Аудитория |
|----------|------------|-----------|
| [README.md](../README.md) | **Главная точка входа:** цель, архитектура, Docker-dev, структура репо, workflows (обзор), **ссылки Acurast** (Getting Started, Build, Tools, Processors, Protocol) | Все |
| [AGENTS.md](../AGENTS.md) | Инструкции Cursor Cloud Agents / Automations / CLI: git/PR порядок, container-only проверки, архитектурные правила, GitHub Environments secrets | Агенты |

---

## Уровень 1 — план и прогресс

| Документ | Назначение |
|----------|------------|
| [roadmap.md](roadmap.md) | Фазы 0–5, deliverables, **checkpoint — следующая сессия** (canary vs mainnet vs operator relay), метрики успеха |

Любая задача «что делать дальше» — сначала таблица статуса и checkpoint в roadmap.

---

## Уровень 2 — специализированная документация

| Документ | Когда читать |
|----------|--------------|
| [nostr-protocol.md](nostr-protocol.md) | Kinds, tags, JSON-схемы, Acurast transport (`httpGET`/`httpPOST`, не `_STD_.ws` для relay) |
| [relay-ops.md](relay-ops.md) | Хостинг relay, Selectel GitOps, секреты environment **relay**, troubleshooting OpenStack |
| [github-actions.md](github-actions.md) | CI, canary deploy, official Acurast example smoke, validate/provision/deploy/uptime relay, branch protection, секреты **canary** / **relay** |
| [economics.md](economics.md) | ROI, treasury, cost/revenue attribution; модели **pull-oracle** (Phase 3) и **AI module** (Phase 5) |
| [collective-intelligence.md](collective-intelligence.md) | CI: economic selection, NIP-90 market, multi-source oracle; ссылка на `oracle-feed` |

**Связи:**

- Nostr-события → `nostr-protocol.md` · relay на VPS → `relay-ops.md` · GHA → `github-actions.md`
- Активный ops-путь (Phase 2): roadmap checkpoint → `relay-ops.md` + `github-actions.md`

---

## Уровень 3 — модульные и инструментальные

| Документ | Назначение |
|----------|------------|
| [modules/module-template/README.md](../modules/module-template/README.md) | Scaffold нового Acurast-модуля (`new-module.sh`) |
| [modules/acurast-example-smoke/README.md](../modules/acurast-example-smoke/README.md) | Контрольный canary smoke на базе official Acurast `app-benchmark-nodejs` |
| [modules/oracle-feed/README.md](../modules/oracle-feed/README.md) | Pull-oracle Phase 3: NIP-90 jobs, feeds, env |
| [.cursor/BUGBOT.md](../.cursor/BUGBOT.md) | Правила авто-ревью PR (секреты, bundle, Nostr/Acurast) |
| [.cursor/environment.json](../.cursor/environment.json) | Cloud Agent VM: setup/verify команды |

---

## Внешние источники (не в git)

| Ресурс | Назначение |
|--------|------------|
| [Acurast Docs](https://docs.acurast.com/) | Runtime API, deploy, TEE |
| [Nostr NIPs](https://github.com/nostr-protocol/nips) | Протокол |
| [Selectel Terraform](https://docs.selectel.ru/terraform/quickstart/) | OpenStack провижининг |

---

## Правила обновления карты (агенты и PR)

При **любом** из изменений ниже — обновите **эту карту** (`docs/map.md`) и при необходимости блок «Документация» в [README.md](../README.md):

1. **Новый файл `*.md`** в корне, `docs/` или значимый README модуля.
2. **Переименование / удаление** документа.
3. **Смена роли документа** (например ops → roadmap checkpoint).
4. **Новый workflow** или environment — отразить в `github-actions.md` и здесь.
5. **Смена активной фазы** — обновить [roadmap.md](roadmap.md) (обязательно) и checkpoint.

**Порядок правок в PR с документацией:**

1. Содержание целевого doc.
2. [roadmap.md](roadmap.md) — если меняется статус, фаза или checkpoint.
3. **docs/map.md** — если меняется состав или связи.
4. [README.md](../README.md) — только если меняется обзор, структура репо или верхний список docs.

Не дублировать checkpoint в нескольких файлах: **единственное место «следующая сессия»** — [roadmap.md#checkpoint--следующая-сессия](roadmap.md#checkpoint--следующая-сессия); ops-детали — в [relay-ops.md](relay-ops.md) со ссылкой на roadmap.

---

## Быстрый выбор по задаче

| Задача | Читать |
|--------|--------|
| Первое знакомство с проектом | README → roadmap |
| Cursor Agent / Cloud Agent | README → **AGENTS** → roadmap → map |
| Nostr kinds / heartbeat | nostr-protocol.md |
| Selectel VM / relay provision | roadmap checkpoint → relay-ops → github-actions |
| CI / deploy canary / deployment diagnostics | github-actions.md |
| Статус deployment (SDK + CLI, без Hub/DevTools) | github-actions.md → `inspect-canary-deployments.yml`, `fetch-acurast-deployment-status.mjs` |
| DevTools processor logs (опционально, API часто 502) | github-actions.md → `inspect-canary-devtools.yml` |
| Acurast support escalation (canary 378420–378428) | [acurast-escalation-378425.md](acurast-escalation-378425.md) |
| Новый модуль | module-template README → AGENTS |
| ROI / promote-pause-kill / oracle / AI economics | economics.md → roadmap Phase 3–5 |
| Collective intelligence / oracle-feed | collective-intelligence.md → modules/oracle-feed |
