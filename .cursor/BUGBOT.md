# Bugbot rules — NostrHiveMind

**Навигация:** [README](../README.md) · [docs/map.md](../docs/map.md) · [AGENTS.md](../AGENTS.md)

---

## Security (blockers)

- **No secrets in source or bundles** — mnemonics, API keys, private keys must use `.env` + `includeEnvironmentVariables` / Cursor Secrets. Flag any hardcoded `ACURAST_MNEMONIC`, `nsec`, hex private keys.
- **No committing `.env`** — only `.env.example` with placeholders.
- **Bundle review** — ensure webpack/esbuild does not inline secrets from `process.env` at build time unless explicitly intended for public config.

## Acurast

- Deploy artifacts must be a **single** `dist/bundle.js` per module.
- Target **Node.js v20**; avoid APIs unavailable in [Acurast runtime](https://docs.acurast.com/developers/job-runtime-environment/) (`httpGET`/`httpPOST`, `_STD_`, not always `fetch` unless bundled).
- Production `acurast.json`: `onlyAttestedDevices: true`, prefer `mutability: Immutable`.
- Local/dev code must install **mock `_STD_`** when undefined (see `modules/hello/src/runtime/local-std.ts`).
- Do not introduce a separate vault microservice — use `_STD_.signers` + `_STD_.env`.

## Nostr

- Encrypted payloads: **NIP-44**, not deprecated NIP-04.
- Job flows: **NIP-90** kinds (`5000–5999` / `6000–6999` / `7000`).
- Replaceable agent state: **NIP-33** parameterized replaceable events.
- Do not treat Nostr relays as authoritative financial state.

## TypeScript / modules

- New business logic belongs in `modules/<name>/` with its own `acurast.json`.
- Shared types/interfaces: prefer `packages/` when introduced; avoid cross-module deep imports until packages exist.
- Tests required for non-trivial business logic changes.

## Docker / CI parity

- CI path: `docker compose` via [.github/workflows/ci.yml](../.github/workflows/ci.yml) or `./scripts/dev`.
- Do not add host-only npm scripts that bypass Docker without documenting a fallback in AGENTS.md.

## Out of scope for automated review

- `acurast live` / phone processor setup
- Real TEE signing behavior
- Canary deploy execution (requires human-funded wallet)
