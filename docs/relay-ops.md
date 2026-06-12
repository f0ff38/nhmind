# Nostr relay — ops и выбор хостинга

**Навигация:** [README](../README.md) · [map.md](map.md) · [roadmap.md](roadmap.md) (checkpoint) · [github-actions.md](github-actions.md)

Руководство по production relay для nhmind: требования Acurast, выбор VPS, уроки из экосистемы Nostr (в т.ч. [Nosflare](https://github.com/Spl0itable/nosflare)).

**Статус (2026-06):** validate ✅, plan ✅, **apply ✅**, **Deploy Relay** + WSS smoke ✅, Selectel LE TLS ✅. Блокер Phase 2: **hello heartbeat на relay** (Deploy Canary smoke ❌) — **[roadmap → checkpoint](roadmap.md#checkpoint--следующая-сессия)** (единственный список «что дальше»).

---

## Роль relay в nhmind

| Компонент | Зависимость от relay |
|-----------|---------------------|
| `hello` | Публикует heartbeat `30090` |
| `coordinator` | Читает heartbeat, публикует registry `30092` и scorecard `30091` |
| Acurast processor | `httpGET`/`httpPOST` к `RELAY_URL` + DNS TXT `_acu.<host>` |

Локально: `docker compose --profile relay` → `ws://nostr-relay:8080` (порт `7777` на хосте).

Canary/production: `RELAY_HOSTNAME` в GitHub environment **canary** → [deploy-canary.yml](../.github/workflows/deploy-canary.yml) собирает `RELAY_URL=wss://<RELAY_HOSTNAME>/` в `.env` модуля.

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
| **Selectel** (облачные серверы) | PTR в **IP-адреса**, DNS-хостинг, Terraform/OpenStack API, оплата РФ | **Выбран** для canary relay; сеть: приватная подсеть + 1 публичный IP (не `/29`) |
| Аналоги (Timeweb Cloud, …) | Тот же чеклист: KVM + PTR + SSH | Сверять PTR **до** заказа |

**Одна нода** достаточна для Phase 2. Георезерв и второй relay — [Phase 5 backlog](roadmap.md#backlog-после-phase-5) (multi-relay quorum).

### Что не подходит как primary `RELAY_URL`

| Решение | Причина |
|---------|---------|
| [Nosflare](https://github.com/Spl0itable/nosflare) / Cloudflare Workers | Anycast IP Cloudflare → PTR не совпадает с вашим hostname → Acurast `_acu` whitelist |
| Виртуальный shared-хостинг | Нет root/Docker, лимиты CPU |
| Эфемерные pod (Killercoda, hourly K8s) | Нестабильный IP/DNS, не для coordinator interval |

Nosflare полезен как **источник идей** (ниже), не как замена VPS relay для processor.

---

## Selectel GitOps (провижининг relay)

Цель: один путь из git — VM с Docker/UFW/deploy-user → DNS/PTR → relay compose → smoke → `RELAY_URL` в canary.

### Два workflow (последовательность)

| Этап | Workflow | Что делает |
|------|----------|------------|
| 1. Инфраструктура | `provision-relay-infra.yml` | Terraform: проект (или data source существующего), сеть, VM, floating IP, cloud-init |
| 2. Приложение | `deploy-relay.yml` | SSH (IP из Terraform state) → Selectel LE (DNS-01) → Knox PEM → compose, smoke WSS |

Триггер: **`workflow_dispatch`** (как `deploy-canary.yml`), environment **relay** с required reviewers на `apply`.

### Сеть Selectel (важно)

Для relay достаточно **приватная подсеть + облачный роутер + 1 публичный IP** (floating IP, pool `external-network`). Это обходит квоту **«Публичная подсеть /29»** и дешевле, чем заказывать блок из 5 адресов.

Схема по [документации Selectel](https://docs.selectel.ru/cloud-servers/cloud-networks/public-ip-addresses/): роутер делает 1:1 NAT; PTR и `A`-запись — на внешний floating IP.

### Аутентификация API ([authorization](https://docs.selectel.ru/api/authorization/))

Selectel использует **три типа** токенов; для GitOps нужна **комбинация**:

| Токен | Заголовок | TTL | Кто выписывает | Для чего в nhmind |
|-------|-----------|-----|----------------|-------------------|
| IAM, scope **проект** | `X-Auth-Token` | 24 ч | Сервисный пользователь (Keystone) | OpenStack API через Terraform: VM, сеть, floating IP |
| IAM, scope **аккаунт** | `X-Auth-Token` | 24 ч | Сервисный пользователь | Опционально: квоты, IAM; в CI обычно не нужен |
| **Статический** | `X-Token` | ∞ | Пользователь панели → Профиль → API-ключи | **Только** [сервис учёта IP](https://docs.selectel.ru/api/ip-addresses/) — PTR; **не** работает с OpenStack |

**Рекомендация для GHA:**

1. **Terraform** — логин/пароль **сервисного пользователя** с ролью `member` в scope **Проект** (паттерн из [Terraform quickstart](https://docs.selectel.ru/terraform/quickstart/)): провайдеры `selectel` + `openstack`, `auth_url = https://cloud.api.selcloud.ru/identity/v3`. Пароль — в GitHub Secret; IAM-токен в CI **можно** получать через Keystone POST, но проще отдать password провайдеру (он сам ходит в Keystone).
2. **PTR** — [upsert-relay-ptr.sh](../infra/selectel/scripts/upsert-relay-ptr.sh): `POST`/`PUT` к **IPAM API** `https://api.selectel.ru/ipam/v1/` с `X-Token` (не `domains/v1/ptr` — legacy, HTTP 405). IAM-токены для PTR **не поддерживаются**.
3. **DNS** (DNS hosting actual) — после `apply`: при отсутствии зоны `POST /zones`, затем upsert **A** через [DNS API v2](https://docs.selectel.ru/en/api/dns-actual/). **`SELECTEL_PROJECT_ID`** тот же, что в IAM → Projects и Облачные серверы; для DNS Keystone нужен scope по **имени** проекта — [resolve-selectel-project-name.sh](../infra/selectel/scripts/resolve-selectel-project-name.sh) резолвит имя по id автоматически. Override: `SELECTEL_IAM_PROJECT_NAME`. Опционально `RELAY_DNS_ZONE_ID`.
4. **Не хранить** статический `X-Token` в Terraform state; PTR — shell/curl или маленький script в workflow после `terraform apply`.

Ограничение API по IP: в панели можно [ограничить доступ](https://docs.selectel.ru/api/authorization/) к `https://api.selectel.ru` — для GHA учесть egress GitHub Actions или не включать whitelist на первом этапе.

### Файрвол VM (canary): SSH key-only, HTTPS public

На этапе Terraform ([группа безопасности](https://docs.selectel.ru/cloud-servers/security-groups/about-security-groups/), лимит **200 правил** на пул) для Phase 2 canary:

| Порт | Источник | Зачем |
|------|----------|--------|
| **443/tcp** | `0.0.0.0/0` | Acurast processor, WSS-клиенты |
| **22/tcp** | `0.0.0.0/0` | SSH для GHA deploy и ops; **только по ключу** (нет паролей) |

**:80 закрыт** — LE выпускается в Selectel Certificate Manager (DNS-01), не на VM.

Почему не [Meta API `actions`](https://docs.github.com/ru/authentication/keeping-your-account-and-data-secure/about-githubs-ip-addresses): ~7000+ динамических CIDR, лимит Selectel 200 правил, список меняется — GitHub не рекомендует жёсткий allowlist для hosted runners.

Защита SSH:

- Security group + cloud-init: `PasswordAuthentication no`, пользователь `deploy`, ключ из `RELAY_DEPLOY_SSH_*`
- UFW на VM дублирует 22/443 (второй слой)
- Сканирование порта 22 возможно — для production позже сузить (self-hosted runner, VPN, `/32` operator)

**Файрвол workflow:** [provision-relay-infra.yml](../.github/workflows/provision-relay-infra.yml) — [github-actions.md](github-actions.md#10-provision-relay-vm-selectel).

### Планируемая структура в репозитории

```
infra/selectel/terraform/
├── versions.tf           # openstack 2.1.0, backend s3 (Selectel Object Storage)
├── providers.tf          # openstack only (auth_url, tenant_id hex, region pool)
├── network.tf            # private network, subnet, router, floating IP
├── compute.tf            # keypair, VM, user_data ← cloud-init
├── variables.tf          # flavor_id, pool, az
└── outputs.tf            # public_ip, flavor_id, flavor_name, server_id

infra/selectel/scripts/
├── prepare-openstack-env.sh
├── verify-openstack-auth.sh
├── resolve-relay-flavor.sh   # Nova API auto-pick 2 vCPU / 4096 MB / disk 0 → TF_VAR_flavor_id
├── write-terraform-backend-ci.sh
├── read-relay-public-ip.sh   # terraform output public_ip (deploy + validate)
├── get-openstack-project-token.sh
├── get-selectel-dns-token.sh    # DNS API: name scope from SELECTEL_PROJECT_ID
├── resolve-selectel-project-name.sh
├── upsert-relay-dns-a.sh     # Selectel DNS A record after apply
├── upsert-relay-ptr.sh       # Selectel IPAM PTR (ipam/v1)
├── issue-relay-le-cert.sh    # LE issue/list (DNS-01, dnsv2)
├── fetch-relay-tls-pem.sh    # Knox → fullchain.pem + privkey.pem
├── verify-selectel-dns-auth.sh
└── verify-selectel-le-auth.sh

infra/selectel/cloud-init/
└── relay-bootstrap.yaml  # Docker, UFW 22+443, deploy-user, /opt/nhmind-relay

infra/nostr-relay/
├── docker-compose.yml    # nginx:1.30.2-alpine + scsibug/nostr-rs-relay:0.10.0
├── nginx.conf
├── config.toml
└── .env.example

.github/workflows/
├── provision-relay-infra.yml   # terraform plan/apply, PTR API, DNS A (Selectel DNS)
└── deploy-relay.yml              # SSH deploy | smoke
```

**Terraform state:** remote backend в [S3 Selectel](https://docs.selectel.ru/terraform/configure-terraform-state-storage/) (`secret.backend.tfvars` только в Secrets, не в git).

**cloud-init (преднастройка VM):** пакеты Docker, пользователь `deploy`, SSH authorized_keys из Terraform `selectel_vpc_keypair_v2`, UFW 22+443. TLS (Selectel LE → Knox) и relay compose — этап 2 (`deploy-relay.yml`), когда известен `RELAY_HOSTNAME`.

### TLS: Selectel Certificate Manager (DNS-01)

Сертификат на **один FQDN** (`RELAY_HOSTNAME`, напр. `nostr.example.com`) — без wildcard.

| Этап | Где | Что |
|------|-----|-----|
| Выпуск / продление | Selectel | [LE API](https://docs.selectel.ru/api/lets-encrypt-certificates/) `POST /issue?dnsv2=true`; авто-renew ~30 дней до expiry |
| Приватный ключ | Knox (Selectel) | Не в git и не в GitHub Secrets; скачивается на deploy |
| Установка на VM | `deploy-relay.yml` | [fetch-relay-tls-pem.sh](../infra/selectel/scripts/fetch-relay-tls-pem.sh) → `/opt/nhmind-relay/certs/` → nginx `:443` |

**Pull-on-deploy:** каждый `deploy-relay` вызывает [issue-relay-le-cert.sh](../infra/selectel/scripts/issue-relay-le-cert.sh) (idempotent: найти по `RELAY_HOSTNAME` или выпустить) и тянет актуальный PEM из [Certificate Manager API](https://docs.selectel.ru/api/certificates-manager/) (`knox_cert_id`).

Опциональный secret **`RELAY_TLS_KNOX_CERT_ID`** — UUID Knox, если в проекте несколько сертов; иначе резолв по домену из LE list API.

**Требования DNS-01:** зона в DNS hosting (actual), NS на Selectel (`a/b/c/d.ns.selectel.ru`), **A** на floating IP relay.

**Миграция с certbot:** **Deploy Relay** с новым кодом (UFW `:80` снимается в `bootstrap-relay.sh`); затем **Provision → apply** убирает правило SG `:80`.

### Секреты GitHub environment **relay**

Сервисный пользователь (Terraform/OpenStack): `member` @ проект **nhmind** — достаточно для VM и сети. `iam.admin` @ аккаунт в CI **не обязателен** (оставлен у вас для bootstrap IAM/S3; позже можно сузить).

| Secret | Когда нужен | Назначение |
|--------|-------------|------------|
| `SELECTEL_SERVICE_USER` | ✅ сейчас | Имя сервисного пользователя |
| `SELECTEL_SERVICE_PASSWORD` | ✅ сейчас | Пароль сервисного пользователя |
| `SELECTEL_ACCOUNT_ID` | ✅ до 1-го `plan` | Номер аккаунта (`domain_name` в провайдере) |
| `SELECTEL_PROJECT_ID` | ✅ до 1-го `plan` | ID проекта облачной платформы **nhmind**: **Продукты → Облачные серверы** → меню проектов → скопировать ID (32 hex, **без** дефисов). Не путать с IAM → Проекты — там другой идентификатор |
| `RELAY_DEPLOY_SSH_PRIVATE_KEY` | ✅ до 1-го `apply` | Ed25519/RSA **private** key (PEM) |
| `RELAY_DEPLOY_SSH_PUBLIC_KEY` | ✅ до 1-го `apply` | OpenSSH public key (пара к private; в TF keypair и `deploy` user) |
| `SELECTEL_AVAILABILITY_ZONE` | ✅ до 1-го `plan` | **Зона доступности** при создании VM: `ru-3a` / `ru-3b` (не пул `ru-3` — он только для `region` в провайдере) |
| `SELECTEL_REGION` | опционально | Пул OpenStack, напр. `ru-3`; если пусто — workflow выводит из `SELECTEL_AVAILABILITY_ZONE` |
| `TF_STATE_S3_BUCKET` | ✅ до 1-го `init` | Бакет S3 Selectel для `terraform.tfstate` |
| `TF_STATE_S3_ACCESS_KEY` | ✅ до 1-го `init` | Access Key S3 (ключ сервисного пользователя или отдельный) |
| `TF_STATE_S3_SECRET_KEY` | ✅ до 1-го `init` | Secret Key S3 |
| `TF_STATE_S3_REGION` | опционально | Пул бакета S3, напр. `ru-3` — **должен совпадать** с регионом контейнера. Если пусто — берётся `SELECTEL_REGION` или из `SELECTEL_AVAILABILITY_ZONE` (`ru-3a` → `ru-3`) |
| `SELECTEL_STATIC_TOKEN` | после VM, до PTR | Статический ключ панели (`X-Token`), **не** сервисный пользователь — [PTR API](https://docs.selectel.ru/api/ip-addresses/) |
| `RELAY_HOSTNAME` | до PTR/DNS/TLS | FQDN, напр. `nostr.example.com` (PTR = этот hostname) |
| `RELAY_DNS_ZONE` | опционально | Зона в Selectel DNS, напр. `example.com` — если не задана, выводится из `RELAY_HOSTNAME` (`nostr.example.com` → `example.com`) |
| `RELAY_DNS_ZONE_ID` | опционально | UUID **доменной зоны** DNS hosting (actual); не UUID из `/registrar/` |
| `SELECTEL_IAM_PROJECT_NAME` | опционально | Override имени проекта для DNS API; иначе резолвится из `SELECTEL_PROJECT_ID` |
| `RELAY_TLS_KNOX_CERT_ID` | опционально | UUID Knox-серта; если пусто — авто по `RELAY_HOSTNAME` в LE list API |

**Не секрет:** floating IP relay — **`terraform output public_ip`** (S3 state). Workflow **Deploy Relay** и validate stage `deploy` читают его автоматически; ручной secret `RELAY_SSH_HOST` **не нужен**. SSH user — `deploy` (cloud-init).

**Не секреты** (в `terraform.tfvars` или workflow input): pool `ru-3` (= `region` OpenStack-провайдера). **Flavor:** в CI auto-resolve через [resolve-relay-flavor.sh](../infra/selectel/scripts/resolve-relay-flavor.sh) (2 vCPU / 4096 MB / disk 0); override — workflow input `flavor_id` или `terraform.tfvars`.

**Секреты только в environment `relay`:** Settings → **Environments** → **relay** → Environment secrets (не Repository secrets).

**Проверка секретов:** workflow [**Validate Relay Secrets**](../.github/workflows/validate-relay-secrets.yml) (`workflow_dispatch`, environment **relay**).

| Режим | Формат | Live-проверки |
|-------|--------|---------------|
| `provision` | presence + формат | SSH keypair, S3 state bucket, Keystone (OpenStack), `X-Token` (Balance API) |
| `deploy` | presence + формат | SSH keypair, Terraform state, Selectel LE API, SSH login to VM (`public_ip` из state) |
| `all` | оба | все выше |

Значения не логируются — только «пусто / неверный формат / HTTP-код / checklist».

### Troubleshooting: `Authentication failed` (OpenStack)

Если **Provision Relay Infra** или validate падает на OpenStack/Keystone:

| Проверка | Детали |
|----------|--------|
| **SELECTEL_ACCOUNT_ID** | Номер аккаунта (правый верх панели), не имя проекта |
| **SELECTEL_PROJECT_ID** | **Облачные серверы → nhmind → ID** (32 hex). Не IAM → Проекты |
| **Сервисный пользователь** | Роль **member** в scope **Проект nhmind** (тот же `SELECTEL_PROJECT_ID`) |
| **Пароль** | Пересохранить secret без пробела/переноса строки в конце |
| **Пул** | `SELECTEL_AVAILABILITY_ZONE=ru-3a` → region `ru-3` (workflow нормализует) |

| **S3 validate SSL error on GHA** | `CERTIFICATE_VERIFY_FAILED` / self-signed chain — AWS CLI on runners; verify script uses `--no-verify-ssl` (credentials check only). Terraform init uses `skip_credentials_validation`; plan may still work (Go trust store differs) |

Workflow нормализует project id в **32 hex** (как в панели Облачные серверы) и вызывает Keystone **в два шага**: identity → project scope. Полный JSON ответа печатается в лог (без пароля).

### Troubleshooting: `apply` failed (partial state)

Если **apply** оборвался (VM в `ERROR`, `SecurityGroupRuleExists`, и т.п.):

1. **Provision Relay Infra** → **`destroy`** (environment **relay**) — снимает ресурсы из Terraform state.
2. В панели **Облачные серверы** удалите вручную сервер в статусе `ERROR`, если он остался после destroy.
3. Обновите репо (fix в `security.tf` / порядок FIP) и снова **`plan`** → **`apply`**.

| Симптом | Причина | Действие |
|---------|---------|----------|
| `SecurityGroupRuleExists` egress | Selectel уже создаёт default egress на новой SG | egress rule убран из Terraform; `destroy` → `apply` |
| Instance `ERROR` / `%!s(<nil>)` | частичный apply, FIP до VM, orphan volume, **или нет места в AZ** | см. строку ниже; `destroy` → сменить AZ → `apply` |
| Панель: «не хватает свободных ресурсов» в **ru-3a** | сегмент перегружен (capacity), не баг Terraform | **destroy** → AZ **`ru-3b`**: secret `SELECTEL_AVAILABILITY_ZONE` или workflow input `availability_zone=ru-3b` → **apply** |
| PTR API **HTTP 405** `Method Not Allowed` | старый endpoint `domains/v1/ptr` | используйте **IPAM** `ipam/v1` ([upsert-relay-ptr.sh](../infra/selectel/scripts/upsert-relay-ptr.sh)); повторный **apply** с `set_ptr=true` |
| PTR **HTTP 409** `ptr_already_exists` на повторном apply | PTR уже указывает на `RELAY_HOSTNAME` | idempotent upsert в [upsert-relay-ptr.sh](../infra/selectel/scripts/upsert-relay-ptr.sh); повторный apply безопасен |
| DNS A: **Keystone HTTP 401** | token script использовал UUID project id; Terraform — hex | обновите repo; повторный **apply** с `set_dns_a=true`; при необходимости secret `SELECTEL_IAM_PROJECT_NAME` (IAM → Проекты → имя) |
| DNS A: **zero zones** | **Доменные зоны = 0** (есть только **Домены** registrar) | повторный **apply** с `set_dns_a=true` — [upsert-relay-dns-a.sh](../infra/selectel/scripts/upsert-relay-dns-a.sh) создаёт зону через `POST /zones`; затем NS на Selectel |

**Environment canary** (отдельно): secret **`RELAY_HOSTNAME`** (тот же FQDN, что в **relay**); отдельный `RELAY_URL` не нужен — workflow собирает `wss://<host>/`.

**Bootstrap S3 state (один раз вручную):** бакет в Object Storage + S3-ключ с read/write на бакет ([настройка state](https://docs.selectel.ru/terraform/configure-terraform-state-storage/)).

### Ручные шаги (вне Terraform или до первого apply)

- **Доменная зона** в DNS hosting (actual): создаётся автоматически при `set_dns_a=true` (`POST /zones`), если в панели **Доменные зоны: 0** (registrar **Домены** — отдельный продукт).
- Делегирование NS на Selectel (`a/b/c/d.ns.selectel.ru`) — **один раз** после появления зоны (вручную у регистратора).
- Квоты: **«Публичные IP»** ≥ 1 в выбранном пуле (не `/29`).
- TXT `_acu.nostr.<домен>` — после известны IP и кошельки (`show-acurast-address.mjs`).
- Баланс Selectel для pay-as-you-go.

### Exit criteria GitOps-шага

1. `workflow_dispatch` → provision создаёт VM с публичным IP и cloud-init.
2. PTR = `RELAY_HOSTNAME`, **A** upsert через Selectel DNS API (workflow, `set_dns_a=true`).
3. `deploy-relay` поднимает relay; smoke проходит.
4. `RELAY_HOSTNAME` в canary → **Deploy Canary** → heartbeat в DevTools.

Подробнее про workflows и секреты: [github-actions.md](github-actions.md).

---

## Планируемая схема приложения (relay на VM)

```
infra/nostr-relay/
├── docker-compose.yml      # nginx:1.30.2-alpine + scsibug/nostr-rs-relay:0.10.0
├── nginx.conf              # TLS, WebSocket upgrade, rate limit
├── config.toml             # nostr-rs-relay (limits, allowlist — см. ниже)
└── .env.example            # RELAY_HOSTNAME=nostr.example.com
```

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
2. **Firewall:** SG `22`/`443` + SSH key-only (canary: `0.0.0.0/0:22`).
3. **nginx stable ≥ 1.30.2** в Docker (pin в compose), не полагаться на версию панели хостера.
4. **Relay не на публичном :8080** — только через nginx `:443`.
5. **TLS:** Selectel Certificate Manager LE (DNS-01); ключ в Knox, pull-on-deploy; продление на стороне Selectel.
6. **Canary write policy:** pubkey allowlist в `nostr-rs-relay` — снижает спам на открытом relay.
7. **Секреты:** SSH key только в GitHub environment **relay**; `RELAY_HOSTNAME` в **canary** (→ `RELAY_URL` в workflow).
8. **Без CF proxy** на hostname processor (серое DNS / прямой `A`).

---

## Чеклист первого запуска

1. [x] **Validate Relay Secrets** → `provision` (environment **relay**)
2. [x] **Provision Relay Infra** → `plan` (15 to add; flavor `BL1.2-4096`)
3. [x] **Provision Relay Infra** → `apply`, `set_ptr: true`, `set_dns_a: true`
4. [x] **Deploy Relay** → `deploy` или `all`
5. [x] DNS: TXT `_acu.<RELAY_HOSTNAME>` — автоматически в **Deploy Canary** (`compute-acu-txt` + `upsert-acu-txt`)
6. [x] Smoke WSS (**Deploy Relay** → `smoke`)
7. [x] GitHub **canary** → secret `RELAY_HOSTNAME`
8. [ ] **Deploy Canary → hello** — on-chain ✅; smoke heartbeat `30090` на relay ❌ ([checkpoint](roadmap.md#checkpoint--следующая-сессия))
9. [ ] **Deploy Canary → coordinator** — registry `30092` + scorecard `30091` (после hello heartbeat)

TXT hash: формула в [Acurast Network docs](https://docs.acurast.com/developers/job-runtime-environment/#network); адреса кошельков — `node scripts/show-acurast-address.mjs modules/<name>`.

---

## Известный риск: HTTP на processor

На processor транспорт — **HTTP POST** (`packages/nostr-client` → `acurast-http`), не WebSocket. `nostr-rs-relay` — WebSocket. nginx проксирует WSS для клиентов; для processor может понадобиться **HTTP→WS адаптер** в том же compose — проверить на шаге 9 чеклиста.

---

## Ссылки

- [Selectel — аутентификация API](https://docs.selectel.ru/api/authorization/)
- [Selectel — Terraform quickstart](https://docs.selectel.ru/terraform/quickstart/)
- [Selectel — сервер с публичным IP (Terraform)](https://docs.selectel.ru/en/terraform/examples/cloud-networks/create-servers/create-server-with-public-ip/)
- [Selectel — PTR API](https://docs.selectel.ru/api/ip-addresses/)
- [Spl0itable/nosflare](https://github.com/Spl0itable/nosflare) — serverless relay (идеи, не primary для nhmind)
- [scsibug/nostr-rs-relay](https://github.com/scsibug/nostr-rs-relay) — relay в dev compose
- [nginx stable](https://nginx.org/) — для reverse proxy pin `1.30.2+`
- [Acurast network whitelist](https://docs.acurast.com/developers/job-runtime-environment/#network)
