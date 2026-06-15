# Acurast Example Smoke

Control canary deployment based on Acurast's official `app-benchmark-nodejs`
example from [`Acurast/acurast-example-apps`](https://github.com/Acurast/acurast-example-apps).

Purpose: isolate whether Acurast canary processors execute a known-good native
Node.js workload independently of nhmind's Nostr/relay code.

## Behavior

- Runs the official benchmark-style workload: CPU, crypto, JSON, file I/O, and memory.
- Runs a best-effort network benchmark against `speed.cloudflare.com`.
- Prints a JSON payload to runtime logs.
- If `WEBHOOK_URL` is configured, POSTs the payload to that URL.

`WEBHOOK_URL` is optional so a canary deployment can still test processor
execution/reporting without depending on a third-party webhook.

## Local

```bash
NHIND_MODULE_DIR=modules/acurast-example-smoke ./scripts/dev install
NHIND_MODULE_DIR=modules/acurast-example-smoke ./scripts/dev test
NHIND_MODULE_DIR=modules/acurast-example-smoke ./scripts/dev bundle
NHIND_MODULE_DIR=modules/acurast-example-smoke ./scripts/dev run
```

## Canary

Use `.github/workflows/deploy-acurast-example-smoke.yml`.

The workflow uses environment **canary** for the mnemonic. If available, set
`ACURAST_EXAMPLE_WEBHOOK_URL` in that environment; otherwise provide the
manual `webhook_url` input or leave both empty to skip POST.
