# Acurast Example Smoke

Control canary deployment based on Acurast's official `app-benchmark-nodejs`
example from [`Acurast/acurast-example-apps`](https://github.com/Acurast/acurast-example-apps).

Purpose: isolate whether Acurast canary processors execute a known-good native
Node.js workload independently of nhmind's Nostr/relay code.

## Behavior

- Runs the official benchmark-style workload: CPU, crypto, JSON, file I/O, and memory.
- Runs a best-effort network benchmark against `speed.cloudflare.com`.
- Prints a JSON payload to runtime logs.
- If `WEBHOOK_URL` is configured, POSTs breadcrumb telemetry and the final
  payload to that URL.

`WEBHOOK_URL` is optional so a canary deployment can still test processor
execution/reporting without depending on a third-party webhook.

Breadcrumb events are best-effort and never fail the workload: `started`,
`std-loaded`, `bench-start`, `bench-done`, `network-start`, `network-done`,
`payload-ready`, `done`, and `catch-error`.

Ultra-minimal mode is enabled with `EXAMPLE_SMOKE_MINIMAL=1`. It sends only
`started`, `std-loaded`, `minimal-done`, the final minimal payload, and `done`,
then exits without running the benchmark or network test.

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
manual `webhook_url` input or leave both empty to skip POST. Use
`minimal_smoke=true` for the ultra-minimal processor/reporting repro.

## Mainnet

Use `.github/workflows/deploy-acurast-example-smoke-mainnet.yml`.

The workflow uses environment **mainnet** for `ACURAST_MNEMONIC_MAINNET`.
For breadcrumb telemetry, set `ACURAST_EXAMPLE_WEBHOOK_URL` in that environment
or provide the manual `webhook_url` input. Use `minimal_smoke=true` for the
ultra-minimal processor/reporting repro.

## Live Code Diagnostic

Use Acurast Live Code when DevTools web/API is unavailable but processor
console output is needed. This is a manual operator flow and requires a
live-code processor; it does not inspect an already registered deployment.

```bash
# One-time setup: follow the Acurast CLI prompts for a live-code processor.
ACURAST_MNEMONIC="..." scripts/acurast-live-example-smoke.sh setup --network mainnet

# After the processor is ready, stream console.log output and runtime errors.
ACURAST_MNEMONIC="..." scripts/acurast-live-example-smoke.sh run --network mainnet --skip-install
```

Optional breadcrumb endpoint:

```bash
ACURAST_MNEMONIC="..." scripts/acurast-live-example-smoke.sh run \
  --network mainnet \
  --webhook-url "https://example.com/webhook" \
  --skip-install
```

Expected success signal in live logs: `acurast-example-smoke entrypoint`,
breadcrumb events, and the final JSON payload. If Live Code prints these while
scheduled deployments still expire with `sla 0/1`, the bundle itself starts on a
processor and the remaining failure is likely in scheduled execution/reporting.
