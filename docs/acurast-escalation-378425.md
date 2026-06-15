# Acurast support escalation — canary execution (378420–378428)

**Status:** opened as [Acurast/acurast-cli#140](https://github.com/Acurast/acurast-cli/issues/140) · **network:** Canary · **modules:** `modules/hello`, `modules/acurast-example-smoke`

## Wallet

| Field | Value |
|-------|-------|
| Deployment wallet | `5CAG2e4hcYLoU6j1J27wrWU6pqGX4StyaDYEfmdvWfkCmRn7` |
| Hub (minimal **378425**) | https://hub.acurast.com/job-detail/acurast-5CAG2e4hcYLoU6j1J27wrWU6pqGX4StyaDYEfmdvWfkCmRn7-378425 |

## Deployment IDs (canary)

| ID | Config | Deploy run / notes |
|----|--------|-------------------|
| 378420–378422 | earlier attempts | same ack → Expired pattern |
| **378423** | operator relay (canary) | pre-window ack **1/1**, sla **0/1** → post-window **Expired**, ack **0/0** |
| **378424** | A/B `RELAY_SKIP_WHITELIST=1`, `wss://relay.damus.io/` | same outcome ([PR #74](https://github.com/f0ff38/nhmind/pull/74)) |
| **378425** | minimal `HELLO_MINIMAL=1`, damus, skip whitelist | same outcome ([PR #76](https://github.com/f0ff38/nhmind/pull/76), [run 27469893555](https://github.com/f0ff38/nhmind/actions/runs/27469893555)) |
| **378426** | operator relay after env fix | same outcome ([run 27472258038](https://github.com/f0ff38/nhmind/actions/runs/27472258038)) |
| **378427** | diagnostic runtime: `HELLO_MINIMAL=1`, 300s execution/start-delay, 50 cACU reward | same outcome ([PR #86](https://github.com/f0ff38/nhmind/pull/86), [run 27491479667](https://github.com/f0ff38/nhmind/actions/runs/27491479667), final inspect [27491718496](https://github.com/f0ff38/nhmind/actions/runs/27491718496)) |
| **378428** | official Acurast example smoke: adapted `app-benchmark-nodejs`, 300s execution/start-delay, 50 cACU reward | same outcome ([PR #88](https://github.com/f0ff38/nhmind/pull/88), [run 27526394107](https://github.com/f0ff38/nhmind/actions/runs/27526394107)) |

## Evidence — **378425** (minimal smoke)

| Phase | Result |
|-------|--------|
| Register + pre-window ack | ✅ ack **1/1**, sla **0/1** |
| Assigned processor (pre-window) | `5GEr1Nd2XHHddsXjXrXtdQQVT3NnVrUeZB2hFXgpr1n19DBP` |
| Execution window | `2026-06-13T14:52:09Z` → `2026-06-13T14:53:09Z` (60s) |
| Post-window SDK inspect ([run 27470279264](https://github.com/f0ff38/nhmind/actions/runs/27470279264)) | ❌ **Expired**; ack **0/0**; assignments cleared |
| Smoke `30090` | ⏭ skipped (`minimal_smoke=true`) |
| Processor execution logs | **Not obtained** — see below |

**Isolation conclusion:** relay/DNS, Nostr client, and bundle JS logic are ruled out. Minimal bundle (`console.log` only: `hello-minimal-start` / `hello-minimal-done`) reproduces the same on-chain outcome as operator-relay canary deploy and A/B public relay.

## Evidence — **378427** (diagnostic runtime)

| Phase | Result |
|-------|--------|
| Runtime override | `execution.maxExecutionTimeInMs=300000`, `maxAllowedStartDelayInMs=300000`, `maxCostPerExecution=50000000000` |
| Register + pre-window ack | ✅ ack **1/1**, sla **0/1** |
| Assigned processor (pre-window) | `5FHmaR9P6sRQYStXRfpneHsGvJbvXnnPcxWag5YPVEZoYNCJ` |
| Execution window | `2026-06-14T07:14:27Z` → `2026-06-14T07:19:27Z` (300s) |
| Final post-window SDK inspect ([run 27491718496](https://github.com/f0ff38/nhmind/actions/runs/27491718496)) | ❌ **Expired**; ack **0/0**; assignments cleared |

**Additional isolation conclusion:** short execution/report window and low reward are unlikely root causes.

## Evidence — **378428** (official Acurast example smoke)

| Phase | Result |
|-------|--------|
| Source workload | `modules/acurast-example-smoke`, adapted from official `Acurast/acurast-example-apps` `app-benchmark-nodejs` |
| Runtime config | `execution.maxExecutionTimeInMs=300000`, `maxAllowedStartDelayInMs=300000`, `maxCostPerExecution=50000000000`, `onlyAttestedDevices=false` |
| Register + pre-window ack | ✅ ack **1/1**, sla **0/1** |
| Assigned processor (pre-window) | `5E1yebdEpkmv5gD2UJs1jsb2sPzqNUa6oZHbiekwYxE4NLJ3` |
| Execution window | `2026-06-15T05:45:57Z` → `2026-06-15T05:50:57Z` (300s) |
| Final post-window SDK inspect ([run 27526394107](https://github.com/f0ff38/nhmind/actions/runs/27526394107)) | ❌ **Expired**; ack **0/0**; assignments cleared |

**Additional isolation conclusion:** the failure is not limited to `nhmind` hello/Nostr code. A known official-example workload registers and is acknowledged, then reaches the same Expired/no-SLA outcome.

## Deployment config (relevant fields)

From `modules/hello/acurast.json` (canary):

- `onlyAttestedDevices: false`
- `maxAllowedStartDelayInMs: 60000`
- `enableDevtools: true`
- `maxNetworkRequests: 10`
- `mutability: Mutable`
- Minimal path: env `HELLO_MINIMAL=1` (workflow input `minimal_smoke=true`)
- Diagnostic path: workflow input `diagnostic_runtime=true` (hello only; temporary checkout override, normal `acurast.json` defaults unchanged)

## Execution logs — what we tried

| Path | Result |
|------|--------|
| GHA deploy + inspect logs ([27469893555](https://github.com/f0ff38/nhmind/actions/runs/27469893555), [27470279264](https://github.com/f0ff38/nhmind/actions/runs/27470279264)) | On-chain status only; **`hello-minimal-start` not present** (expected — runtime logs are on processor) |
| Artifact `acurast-deploy-hello-378425` + `inspect-canary-deployment-cli.sh` | CLI Assignments JSON; no execution stdout |
| DevTools API ([run 27470313002](https://github.com/f0ff38/nhmind/actions/runs/27470313002)) | **`api.devtools.acurast.com` → HTTP 502** on `/`, `/health`, `/v1/auth/view-key`; log fetch skipped |
| Hub Reports (web) | **Manual step** — operator must open Hub job detail → Reports tab; public web fetch returns only SPA shell |

## Questions for Acurast support

1. Processors acknowledged deployments **378425** (`5GEr1Nd2XHHddsXjXrXtdQQVT3NnVrUeZB2hFXgpr1n19DBP`) and **378427** (`5FHmaR9P6sRQYStXRfpneHsGvJbvXnnPcxWag5YPVEZoYNCJ`) but reported **sla 0/1** before the window and **no SLA** after expiry — did the Node.js bundle execute at all? Any crash/attestation/runtime rejection?
2. For a minimal one-shot job (`HELLO_MINIMAL=1`, only `console.log`, no network), what on-chain or Hub signals should we expect when execution succeeds?
3. With `onlyAttestedDevices: false` and diagnostic `maxAllowedStartDelayInMs: 300000`, are there other processor-side gates (bundle size, Node runtime version, reputation) that block execution without failing acknowledgement?
4. DevTools API returned **502** from GitHub Actions (2026-06-13) — is there an alternate API or Hub Reports export for processor stdout for job **378425**?
5. The official-example deployment **378428** was acknowledged by processor `5E1yebdEpkmv5gD2UJs1jsb2sPzqNUa6oZHbiekwYxE4NLJ3` and then expired the same way — is this processor known healthy on Canary for other operators' Node.js deployments?

## Suggested operator next step

1. Open Hub → **378428**, **378427**, and **378425** → **Reports** — look for example benchmark JSON, `hello-minimal-start`, or any stderr.
2. Follow up in [Acurast/acurast-cli#140](https://github.com/Acurast/acurast-cli/issues/140) with any Hub Reports screenshots/log snippets.
3. **Do not** redeploy normal hello or coordinator until Acurast confirms root cause.

Related: [roadmap checkpoint](roadmap.md#checkpoint--следующая-сессия) · [github-actions.md](github-actions.md#4-deploy-canary-из-github-actions)
