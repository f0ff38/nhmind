# Acurast support escalation — hello canary execution (378420–378425)

**Status:** ready to open ticket · **network:** Canary · **module:** `modules/hello`

## Wallet

| Field | Value |
|-------|-------|
| Deployment wallet | `5CAG2e4hcYLoU6j1J27wrWU6pqGX4StyaDYEfmdvWfkCmRn7` |
| Hub (minimal **378425**) | https://hub.acurast.com/job-detail/acurast-5CAG2e4hcYLoU6j1J27wrWU6pqGX4StyaDYEfmdvWfkCmRn7-378425 |

## Deployment IDs (hello canary)

| ID | Config | Deploy run / notes |
|----|--------|-------------------|
| 378420–378422 | earlier attempts | same ack → Expired pattern |
| **378423** | operator relay (canary) | pre-window ack **1/1**, sla **0/1** → post-window **Expired**, ack **0/0** |
| **378424** | A/B `RELAY_SKIP_WHITELIST=1`, `wss://relay.damus.io/` | same outcome ([PR #74](https://github.com/f0ff38/nhmind/pull/74)) |
| **378425** | minimal `HELLO_MINIMAL=1`, damus, skip whitelist | same outcome ([PR #76](https://github.com/f0ff38/nhmind/pull/76), [run 27469893555](https://github.com/f0ff38/nhmind/actions/runs/27469893555)) |

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

## Deployment config (relevant fields)

From `modules/hello/acurast.json` (canary):

- `onlyAttestedDevices: false`
- `maxAllowedStartDelayInMs: 60000`
- `enableDevtools: true`
- `maxNetworkRequests: 10`
- `mutability: Mutable`
- Minimal path: env `HELLO_MINIMAL=1` (workflow input `minimal_smoke=true`)

## Execution logs — what we tried

| Path | Result |
|------|--------|
| GHA deploy + inspect logs ([27469893555](https://github.com/f0ff38/nhmind/actions/runs/27469893555), [27470279264](https://github.com/f0ff38/nhmind/actions/runs/27470279264)) | On-chain status only; **`hello-minimal-start` not present** (expected — runtime logs are on processor) |
| Artifact `acurast-deploy-hello-378425` + `inspect-canary-deployment-cli.sh` | CLI Assignments JSON; no execution stdout |
| DevTools API ([run 27470313002](https://github.com/f0ff38/nhmind/actions/runs/27470313002)) | **`api.devtools.acurast.com` → HTTP 502** on `/`, `/health`, `/v1/auth/view-key`; log fetch skipped |
| Hub Reports (web) | **Manual step** — operator must open Hub job detail → Reports tab |

## Questions for Acurast support

1. Processor `5GEr1Nd2XHHddsXjXrXtdQQVT3NnVrUeZB2hFXgpr1n19DBP` acknowledged deployment **378425** but reported **sla 0/1** before the window and **no SLA** after expiry — did the Node.js bundle execute at all? Any crash/attestation/runtime rejection?
2. For a minimal one-shot job (`HELLO_MINIMAL=1`, only `console.log`, no network), what on-chain or Hub signals should we expect when execution succeeds?
3. With `onlyAttestedDevices: false` and `maxAllowedStartDelayInMs: 60000`, are there other processor-side gates (bundle size, Node runtime version, reputation) that block execution without failing acknowledgement?
4. DevTools API returned **502** from GitHub Actions (2026-06-13) — is there an alternate API or Hub Reports export for processor stdout for job **378425**?
5. Is this processor known healthy on Canary for other operators' Node.js deployments?

## Suggested operator next step

1. Open Hub → **378425** → **Reports** — look for `hello-minimal-start` or any stderr.
2. If Reports empty / DevTools still 502, file this escalation with deployment IDs **378420–378425** and processor address above.
3. **Do not** redeploy hello or coordinator until Acurast confirms root cause.

Related: [roadmap checkpoint](roadmap.md#checkpoint--следующая-сессия) · [github-actions.md](github-actions.md#4-deploy-canary-из-github-actions)
