# Nostr relay — ops и выбор хостинга

Руководство по production relay для nhmind: требования Acurast, выбор VPS, уроки из экосистемы Nostr (в т.ч. [Nosflare](https://github.com/Spl0itable/nosflare)).

**Связанные документы:** [nostr-protocol.md](nostr-protocol.md) · [github-actions.md](github-actions.md) · [roadmap.md](roadmap.md)

**Статус:** хостинг и `infra/nostr-relay/` — в подготовке (ожидаем домен, IP, SSH).

---

## Роль relay в nhmind

| Компонент | Зависимость от relay |
|-----------|---------------------|
| `hello` | Публикует heartbeat `30090` |
| `coordinator` | Читает heartbeat, публикует registry `30092` и scorecard `30091` |
| Acurast processor | `httpGET`/`httpPOST` к `RELAY_URL` + DNS TXT `_acu.<host>` |

Локально: `docker compose --profile relay` → `ws://nostr-relay:8080` (порт `7777` на хосте).

Canary/production: `RELAY_URL=wss://nostr.<ваш-домен>` в GitHub environment **canary** → redeploy через [deploy-canary.yml](../.github/workflows/deploy-canary.yml).

---

## Выбор хостинга (VPS)

### Обязательные параметры

| Параметр | Зачем |
|----------|--------|
| **KVM VPS** (не shared hosting) | Docker, nginx, долгоживущий relay |
| **Публичный IPv4** (или AAAA) | `A`-запись поддомена |
| **Настраиваемый PTR** | Acurast whitelist: reverse DNS + TXT `_acu.<ptr_hostname>` |
| **Порты 22, 443** | SSH (GHA deploy), HTTPS/WSS |
| **Прямой DNS** (`A` → IP VPS) | **Без** Cloudflare proxy / Nosflare edge на hostname processor |

Подробности DNS и TXT: [nostr-protocol.md — Nostr relay на canary](nostr-protocol.md#nostr-relay-на-canary-ops).

### Кандидаты (ориентиры)

| Провайдер | Плюсы для nhmind | Заметки |
|-----------|------------------|---------|
| **Hetzner** (DE/FI) | Дешёвый KVM, PTR в Robot/Cloud, предсказуемый ops | Оплата: часто нужна EU-карта / PayPal; проверить актуальные способы |
| **IHC.ru** | PTR и DNS в [my.ihc.ru](https://my.ihc.ru), российская оплата | KVM, не виртуальный хостинг; см. [KB IHC](https://support.ihc.ru/index.php?_m=knowledgebase&_a=view) |
| Аналоги (Timeweb Cloud, Selectel, …) | Тот же чеклист: KVM + PTR + SSH | Сверять PTR **до** заказа |

**Одна нода** достаточна для Phase 2. Георезерв и второй relay — [Phase 5 backlog](roadmap.md#backlog-после-phase-5) (multi-relay quorum).

### Что не подходит как primary `RELAY_URL`

| Решение | Причина |
|---------|---------|
| [Nosflare](https://github.com/Spl0itable/nosflare) / Cloudflare Workers | Anycast IP Cloudflare → PTR не совпадает с вашим hostname → Acurast `_acu` whitelist |
| Виртуальный shared-хостинг | Нет root/Docker, лимиты CPU |
| Эфемерные pod (Killercoda, hourly K8s) | Нестабильный IP/DNS, не для coordinator interval |

Nosflare полезен как **источник идей** (ниже), не как замена VPS relay для processor.

---

## Планируемая схема из репозитория

Следующий инженерный шаг (после появления домена/IP/SSH):

```
infra/nostr-relay/
├── docker-compose.yml      # nginx:1.30.2-alpine + scsibug/nostr-rs-relay:0.10.0
├── nginx.conf              # TLS, WebSocket upgrade, rate limit
├── config.toml             # nostr-rs-relay (limits, allowlist — см. ниже)
└── .env.example            # RELAY_HOSTNAME=nostr.example.com

.github/workflows/deploy-relay.yml   # workflow_dispatch: deploy | smoke
```

Секреты GitHub environment **relay**: `RELAY_SSH_HOST`, `RELAY_SSH_USER`, `RELAY_SSH_KEY`, `RELAY_HOSTNAME`.

До появления `infra/` — ручной bootstrap по чеклисту в [nostr-protocol.md](nostr-protocol.md).

---

## Уроки из Nosflare (что перенять)

[Nosflare](https://github.com/Spl0itable/nosflare) — serverless relay на Cloudflare Workers + D1 + Durable Objects. Для **публичного Nostr** сильный стек; для **Acurast processor** — не primary (см. выше). Ниже — приёмы, которые имеет смысл перенести на **свой VPS + nostr-rs-relay + nginx**.

### Принять (Phase 2–5)

| Идея | В Nosflare | В nhmind |
|------|------------|----------|
| **Allowlist event kinds** | `allowedEventKinds` в config | Только `30090`–`30092` (Phase 2), позже `5900`/`6900`/`7000` — в `config.toml` relay |
| **Allowlist tags** | `allowedTags` | Требовать tag `client` = `nhmind` на write (или фильтр на read в coordinator) |
| **Allowlist pubkeys** | `allowedPubkeys` | Canary: только deployment keys hello/coordinator (secp256k1 pubkey из DevTools) |
| **Rate limiting** | Worker + CF rules | `limit_req` в nginx; лимиты в nostr-rs-relay |
| **NIP-33 replaceable** | Supported | Основа heartbeat/scorecard/registry — уже в [nostr-protocol.md](nostr-protocol.md) |
| **NIP-11 relay metadata** | `relayInfo` | Имя relay, список NIPs, `limitation` — для мониторинга и клиентов |
| **Deploy из git** | Worker ← repo / Wrangler | `deploy-relay.yml` → SSH + `docker compose up` |
| **Smoke после deploy** | Ручная проверка | GHA: publish test event + `REQ` с filter `#client=nhmind` |
| **Multi-relay reads** | D1 read replicas (global) | Phase 5: список `RELAY_URL` в конфиге, last-signed-wins в coordinator |

### Отложить (не критично для coordinator bus)

| Идея | Почему отложить |
|------|-----------------|
| Pay-to-relay (NIP-42 / zaps) | Автоматические TEE-публикации не платят за доступ |
| NIP-05 validation на write | Модули не используют NIP-05 identity |
| Global duplicate content hash | Узкий антиспам для notes; для `30090` мало пользы |
| Edge mesh (Durable Objects) | Замена — `_STD_.ws` (Phase 3+), не relay |

### Не переносить

| Идея | Почему |
|------|--------|
| Cloudflare Workers / D1 | Конфликт с Acurast whitelist и HTTP-транспортом processor |
| Serverless-only без VPS | Нет контроля PTR и стабильного `A`-записи |
| «Blaster» (NIP-66 fan-out) | Не нужен для закрытой координации модулей |

---

## Безопасность relay (минимальный baseline)

1. **SSH:** только ключи (ed25519), отдельный deploy-user, `PasswordAuthentication no`.
2. **Firewall:** `443` открыт; `22` — по возможности ограничить IP GitHub Actions / ваш IP.
3. **nginx stable ≥ 1.30.2** в Docker (pin в compose), не полагаться на версию панели хостера.
4. **Relay не на публичном :8080** — только через nginx `:443`.
5. **TLS:** Let's Encrypt (certbot/Caddy) или ISPmanager LE — на выбор; автообновление.
6. **Canary write policy:** pubkey allowlist в `nostr-rs-relay` — снижает спам на открытом relay.
7. **Секреты:** SSH key только в GitHub environment **relay**; `RELAY_URL` в **canary**.
8. **Без CF proxy** на hostname processor (серое DNS / прямой `A`).

---

## Чеклист первого запуска (когда будут домен, IP, SSH)

1. [ ] VPS: Docker установлен, пользователь для deploy
2. [ ] `my.ihc.ru` / Hetzner: **hostname** и **PTR** = `nostr.<домен>`
3. [ ] DNS: `A` `nostr.<домен>` → IP
4. [ ] DNS: TXT `_acu.nostr.<домен>` для deploy-кошельков hello и coordinator
5. [ ] Поднять relay (compose или `infra/` из репо)
6. [ ] Smoke WSS с ноутбука (Nostr client или integration test)
7. [ ] GitHub **canary** → `RELAY_URL=wss://nostr.<домен>`
8. [ ] Redeploy hello + coordinator (`Deploy Canary`)
9. [ ] DevTools: heartbeat и scorecard на processor

TXT hash: формула в [Acurast Network docs](https://docs.acurast.com/developers/job-runtime-environment/#network); адреса кошельков — `node scripts/show-acurast-address.mjs modules/<name>`.

---

## Известный риск: HTTP на processor

На processor транспорт — **HTTP POST** (`packages/nostr-client` → `acurast-http`), не WebSocket. `nostr-rs-relay` — WebSocket. nginx проксирует WSS для клиентов; для processor может понадобиться **HTTP→WS адаптер** в том же compose — проверить на шаге 9 чеклиста.

---

## Ссылки

- [Spl0itable/nosflare](https://github.com/Spl0itable/nosflare) — serverless relay (идеи, не primary для nhmind)
- [scsibug/nostr-rs-relay](https://github.com/scsibug/nostr-rs-relay) — relay в dev compose
- [nginx stable](https://nginx.org/) — для reverse proxy pin `1.30.2+`
- [Acurast network whitelist](https://docs.acurast.com/developers/job-runtime-environment/#network)
