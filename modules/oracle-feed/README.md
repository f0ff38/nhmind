# oracle-feed

Pull-oracle business module for NostrHiveMind (Phase 3).

- **Transport:** Nostr NIP-90 (`job_type: oracle`, kinds `5900` / `6900` / `7000`)
- **Execution:** Acurast TEE (`httpGET` to whitelisted price APIs, `_STD_.signers`)
- **Collective intelligence:** multi-source median with outlier drop (see [collective-intelligence.md](../../docs/collective-intelligence.md))
- **Economics:** per-job `bid` (millisats) → `revenue_acu` ([economics.md](../../docs/economics.md))

## Feeds (canary)

| `feed_id` | Sources |
|-----------|---------|
| `btc-usd` | Coinbase, Kraken (USD spot) |
| `eth-usd` | Coinbase, Kraken (USD spot) |

## Env

| Variable | Default | Description |
|----------|---------|-------------|
| `RELAY_URL` | — | Nostr relay (required) |
| `ORACLE_LIST_PRICE_MSATS` | `100` | Minimum job price |
| `ORACLE_MSAT_TO_ACU_RATE` | `10` | Scorecard conversion |
| `ORACLE_JOB_LOOKBACK_SEC` | `3600` | Job poll window |
| `ORACLE_MIN_SOURCES` | `2` | Minimum successful price APIs per job |

## Local dev

```bash
NHIND_MODULE_DIR=modules/oracle-feed ./scripts/dev install
NHIND_MODULE_DIR=modules/oracle-feed ./scripts/dev test
NHIND_MODULE_DIR=modules/oracle-feed ./scripts/dev bundle
NHIND_MODULE_DIR=modules/oracle-feed ./scripts/dev run
```

## Job flow

1. Client publishes `5900` with `bid` ≥ list price and `input.feed_id`.
2. Client publishes `7000` with `status: paid` **from the requester pubkey** (same key as step 1).
3. Module whitelists price API hosts, fetches ≥2 sources, median-aggregates, signs result, publishes `6900`.
4. On failure, module publishes `6900` with `status: error`. Existing `6900` for the same `job_id` is not re-executed.

## Acurast deploy

Before canary deploy, upsert DNS TXT `_acu.<host>` for `api.coinbase.com` and `api.kraken.com` (same pattern as relay whitelist).
