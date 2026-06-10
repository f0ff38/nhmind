# NostrHiveMind (nhmind)

> **GitHub:** [NostrHiveMind](https://github.com/f0ff38/nhmind) · **Agents (Cursor):** `AGENTS.md` · **Roadmap:** `docs/roadmap.md`

Это основной файл проекта, сессия с агентом всегда начинается с этого файла. В файле должна быть понятная агентам структура проекта.

## Продуктовая цель

**NostrHiveMind** — децентрализованная автономная система AI-агентов в TEE на Acurast (DePIN). Координация и state — через **Nostr**; business-модули — Acurast Execution Recipes.

### Ключевые принципы

1. **Самоокупаемость** — `ROI ≥ 1.0`; runway из **BTC** на старте; Module Scorecard для business-модулей.
2. **Полная автономия** — без централизованных серверов и БД в production (Nostr + TEE).
3. **Самообучаемость микросервисов** - использовать нативные ИИ Acurast

## Архитектурные правила
- Все микросервисы должны быть независимыми, легковесными и готовыми к упаковке в Acurast Deployment (минимизировать размер node_modules / зависимостей).
- Прямое хранение приватных ключей в коде **ЗАПРЕЩЕНО**. Все запросы на транзакции идут через микросервис `vault`.
- Каждый business-модуль имплементирует `IBusinessService` (`getProfitability()`, `healthCheck()`) и пишет метрики в Orchestrator.
- Autoscaling только для модулей с положительным ROI (verdict `promote`). См. `docs/economics-and-modules.md`.

## Стек
- **Backend:** TypeScript, Node.js (или Bun для скорости)
- **Блокчейн:** Acurast SDK
- **State (целевое):** Nostr encrypted events

## Команды разработки
- **Сборка:** `npm run build`
- **Тесты:** `npm run test`
- **Валидация деплоя в Acurast:** `npm run acurast:validate`

---

# SYSTEM ARCHITECTURE: TEE AI-AGENT ORCHESTRATION PLATFORM ON ACURAST

> SSOT for Claude Code: `CLAUDE.md` + `docs/economics-and-modules.md`.

---

## 1. System Overview & Self-Sustainability

NostrHiveMind is a **decentralized TEE agent system** on Acurast: coordination via **Nostr**; business modules as Execution Recipes. v0.1 includes a legacy control plane (Orchestrator, Vault, Operator) for local dev.

```
[ Phase 0 — BTC Runway ]
BTC Treasury  →  swap  →  cAcurast / TON  →  Acurast compute
       ↑                                            |
       |         (goal: stop spending BTC)          v
       └──── validated module revenue ──────────────┘

[ Phase 1+ — Module Discovery ]
register → canary (1–3 nodes) → measure 7d → score → promote | pause | kill
```

**Core Goals:**
- **Self-Sustainability (mandatory):** ROI ≥ 1.0 across modules; BTC runway until validated.
- **Full Autonomy (mandatory):** no centralized servers/DBs in production — Nostr state bus + TEE workers.
- **Pluggable Modules:** GameFi and MEV are *experimental* starters; new directions via `IBusinessService` + Module Scorecard.
- **Horizontal Scaling:** Only modules with verdict `promote` are auto-scaled by Orchestrator.
- **Zero-Trust Security:** Private keys never leave the TEE hardware enclave.

---
