#!/usr/bin/env node
/**
 * Fetch Acurast DevTools processor logs from CI (api.devtools.acurast.com).
 * Usage: node scripts/fetch-acurast-devtools-logs.mjs --module hello --job-id 378412 [--wait-ms 0] [--poll-ms 15000] [--timeout-ms 120000]
 *
 * Requires modules/<module>/.env with ACURAST_MNEMONIC (same as acurast deploy).
 */
import { readFileSync } from "fs";
import { resolve } from "path";
import { pathToFileURL } from "url";

const devtoolsApiPath =
  process.env.ACURAST_DEVTOOLS_PKG ??
  "/usr/local/lib/node_modules/@acurast/cli/node_modules/@acurast/devtools/dist/devtools-api.js";
const { getDevtoolsViewKey, buildDevtoolsUrl } = await import(
  pathToFileURL(devtoolsApiPath).href
);

function parseArgs(argv) {
  const out = {
    module: "hello",
    jobId: "",
    waitMs: Number(process.env.INSPECT_WAIT_MS ?? "0"),
    pollMs: 15_000,
    timeoutMs: 120_000,
  };
  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--module") out.module = argv[++i] ?? "";
    else if (arg === "--job-id") out.jobId = argv[++i] ?? "";
    else if (arg === "--wait-ms") out.waitMs = Number(argv[++i] ?? "0");
    else if (arg === "--poll-ms") out.pollMs = Number(argv[++i] ?? "15000");
    else if (arg === "--timeout-ms") out.timeoutMs = Number(argv[++i] ?? "120000");
    else if (arg === "--help" || arg === "-h") {
      console.log(`usage: node scripts/fetch-acurast-devtools-logs.mjs --module <name> --job-id <id> [--wait-ms N] [--poll-ms N] [--timeout-ms N]`);
      process.exit(0);
    }
  }
  if (!out.jobId) {
    console.error("missing --job-id");
    process.exit(1);
  }
  return out;
}

function readMnemonic(moduleDir) {
  const envPath = resolve(moduleDir, ".env");
  const env = readFileSync(envPath, "utf8");
  const match = env.match(/^ACURAST_MNEMONIC=(.+)$/m);
  if (!match) {
    throw new Error(`ACURAST_MNEMONIC not found in ${envPath}`);
  }
  return match[1].trim().replace(/^["']|["']$/g, "");
}

function sleep(ms) {
  return new Promise((resolveSleep) => setTimeout(resolveSleep, ms));
}

function formatLogLines(payload) {
  if (payload == null) return [];
  if (typeof payload === "string") return [payload];
  const entries = Array.isArray(payload)
    ? payload
    : Array.isArray(payload.logs)
      ? payload.logs
      : Array.isArray(payload.items)
        ? payload.items
        : [];
  return entries.map((entry) => {
    if (typeof entry === "string") return entry;
    if (entry && typeof entry.data === "string") return entry.data;
    if (entry && entry.data != null) return JSON.stringify(entry.data);
    return JSON.stringify(entry);
  });
}

async function tryFetchLogs(apiUrl, jobId, viewKey) {
  const headers = {
    Authorization: `Bearer ${viewKey}`,
    "X-View-Key": viewKey,
  };
  const candidates = [
    `${apiUrl}/v1/deployments/${encodeURIComponent(jobId)}/logs`,
    `${apiUrl}/v1/jobs/${encodeURIComponent(jobId)}/logs`,
    `${apiUrl}/v1/logs?jobId=${encodeURIComponent(jobId)}`,
    `${apiUrl}/v1/logs/${encodeURIComponent(jobId)}`,
  ];

  for (const url of candidates) {
    try {
      const res = await fetch(url, { headers });
      const text = await res.text();
      if (!res.ok) {
        console.error(`DevTools logs probe ${res.status} ${url}`);
        continue;
      }
      try {
        return JSON.parse(text);
      } catch {
        return text;
      }
    } catch (error) {
      console.error(
        `DevTools logs probe failed ${url}: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }
  return undefined;
}

async function probeApi(apiUrl) {
  try {
    const res = await fetch(`${apiUrl}/v1/auth/view-key`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jobId: "0" }),
    });
    console.error(`DevTools API probe POST /v1/auth/view-key → HTTP ${res.status}`);
  } catch (error) {
    console.error(
      `DevTools API unreachable: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}

const args = parseArgs(process.argv);
const apiUrl = process.env.ACURAST_DEVTOOLS_API_URL ?? "https://api.devtools.acurast.com";
const uiUrl = process.env.ACURAST_DEVTOOLS_URL ?? "https://devtools.acurast.com";
const moduleDir = resolve(`modules/${args.module}`);
const mnemonic = readMnemonic(moduleDir);

if (args.waitMs > 0) {
  console.log(`Waiting ${args.waitMs}ms before DevTools fetch...`);
  await sleep(args.waitMs);
}

let viewKeyResponse;
try {
  viewKeyResponse = await getDevtoolsViewKey(args.jobId, {
    apiUrl,
    mnemonic,
    logger: {
      debug: (m) => console.error(m),
      error: (m) => console.error(m),
    },
  });
} catch (error) {
  await probeApi(apiUrl);
  const detail = error instanceof Error ? error.message : String(error);
  if (/DevTools API (502|503|504)/.test(detail)) {
    console.error(`::warning::DevTools API temporarily unavailable — skip log fetch (${detail.slice(0, 120)}…)`);
    process.exit(0);
  }
  throw error;
}

const dashboardUrl = buildDevtoolsUrl(
  uiUrl,
  viewKeyResponse.jobId ?? args.jobId,
  viewKeyResponse.viewKey,
);
console.log(`DevTools dashboard: ${dashboardUrl}`);
console.log(`View key expires: ${viewKeyResponse.expiresAt ?? "unknown"}`);

const deadline = Date.now() + args.timeoutMs;
let lastLines = [];

while (Date.now() < deadline) {
  const payload = await tryFetchLogs(apiUrl, args.jobId, viewKeyResponse.viewKey);
  if (payload !== undefined) {
    lastLines = formatLogLines(payload);
    if (lastLines.length > 0) {
      console.log("--- DevTools log lines ---");
      for (const line of lastLines) console.log(line);
      console.log("--- end DevTools log lines ---");
      break;
    }
  }
  const remaining = deadline - Date.now();
  if (remaining <= 0) break;
  console.log(`No DevTools logs yet; polling again in ${args.pollMs}ms (${Math.ceil(remaining / 1000)}s left)...`);
  await sleep(Math.min(args.pollMs, remaining));
}

const heartbeatPublished = lastLines.some((l) => l.includes("heartbeat published"));
const heartbeatSkipped = lastLines.find((l) => l.includes("heartbeat publish skipped"));

if (heartbeatPublished) {
  console.log("DIAGNOSTIC: heartbeat published (processor reached relay publish path)");
  process.exit(0);
}

if (heartbeatSkipped) {
  console.error(`DIAGNOSTIC: ${heartbeatSkipped}`);
  process.exit(1);
}

if (lastLines.length === 0) {
  console.error(
    "::warning::DevTools view key OK but no log lines fetched (API down, unknown GET path, or execution not logged yet).",
  );
  console.error("Check dashboard URL above from a network that can reach devtools.acurast.com.");
  process.exit(2);
}

console.error("::warning::DevTools logs present but no heartbeat line found");
process.exit(2);
