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
| [README.md](../README.md) | **Главная точка входа:** цель, архитектура, Docker-dev, структура репо, workflows (обзор), ссылки | Все |
| [AGENTS.md](../AGENTS.md) | Инструкции Cursor Cloud Agents / Automations / CLI: проверки, архитектурные правила, секреты | Агенты |

---

## Уровень 1 — план и прогресс

| Документ | Назначение |
|----------|------------|
| [roadmap.md](roadmap.md) | Фазы 0–5, deliverables, **checkpoint — следующая сессия**, метрики успеха |

Любая задача «что делать дальше» — сначала таблица статуса и checkpoint в roadmap.

---

## Уровень 2 — специализированная документация

| Документ | Когда читать |
|----------|--------------|
| [nostr-protocol.md](nostr-protocol.md) | Kinds, tags, JSON-схемы, Acurast transport (`httpGET`/`httpPOST`, не `_STD_.ws` для relay) |
| [relay-ops.md](relay-ops.md) | Хостинг relay, Selectel GitOps, секреты environment **relay**, troubleshooting OpenStack |
| [github-actions.md](github-actions.md) | CI, canary deploy, validate/provision relay, branch protection, секреты **canary** / **relay** |
| [economics.md](economics.md) | ROI, treasury, cost/revenue attribution; модели **pull-oracle** (Phase 3) и **AI module** (Phase 5) |

**Связи:**

- Nostr-события → `nostr-protocol.md` · relay на VPS → `relay-ops.md` · GHA → `github-actions.md`
- Активный ops-путь (Phase 2): roadmap checkpoint → `relay-ops.md` + `github-actions.md`

---

## Уровень 3 — модульные и инструментальные

| Документ | Назначение |
|----------|------------|
| [modules/module-template/README.md](../modules/module-template/README.md) | Scaffold нового Acurast-модуля (`new-module.sh`) |
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
| CI / deploy canary | github-actions.md |
| DevTools логи (GHA, не локальная сеть) | github-actions.md → `inspect-canary-devtools.yml` |
| Новый модуль | module-template README → AGENTS |
| ROI / promote-pause-kill / oracle / AI economics | economics.md → roadmap Phase 3–5 |
