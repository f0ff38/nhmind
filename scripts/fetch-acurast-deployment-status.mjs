#!/usr/bin/env node
/**
 * Fetch Acurast deployment status via indexer + on-chain RPC (@acurast/sdk).
 * Works without local .acurast/deploy files (unlike `acurast deployments <id>`).
 *
 * Usage:
 *   node scripts/fetch-acurast-deployment-status.mjs --module hello [--deployment-id 378420] [--network canary]
 */
import { readFileSync, existsSync } from "fs";
import { resolve } from "path";
import { pathToFileURL } from "url";

const sdkChainPath =
  process.env.ACURAST_SDK_CHAIN ??
  "/usr/local/lib/node_modules/@acurast/cli/node_modules/@acurast/sdk/dist/chain/index.js";

const { walletFromMnemonic, AcurastService, getAcknowledgedProcessors } = await import(
  pathToFileURL(sdkChainPath).href
);

const NETWORK_DEFAULTS = {
  canary: {
    rpc:
      process.env.ACURAST_CANARY_RPC ??
      process.env.ACURAST_RPC ??
      "wss://public-rpc.canary.acurast.com",
    indexer:
      process.env.ACURAST_CANARY_INDEXER ??
      "https://dev.indexer.canary.acurast.com/api/v1/rpc",
    indexerApiKey:
      process.env.ACURAST_CANARY_INDEXER_API_KEY ?? "OXuwySHqNSlwwa_qqB-cBw",
    symbol: "cACU",
  },
  mainnet: {
    rpc:
      process.env.ACURAST_MAINNET_RPC ??
      process.env.ACURAST_RPC ??
      "wss://public-rpc.mainnet.acurast.com",
    indexer:
      process.env.ACURAST_MAINNET_INDEXER ??
      "https://dev.indexer.mainnet.acurast.com/api/v1/rpc",
    indexerApiKey:
      process.env.ACURAST_MAINNET_INDEXER_API_KEY ?? "HbLxqSJoPTnzwa_rkF-tYv",
    symbol: "ACU",
  },
};

function parseArgs(argv) {
  const out = { module: "hello", deploymentId: "", network: "canary" };
  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--module") out.module = argv[++i] ?? "";
    else if (arg === "--deployment-id") out.deploymentId = argv[++i] ?? "";
    else if (arg === "--network") out.network = argv[++i] ?? "canary";
    else if (arg === "--help" || arg === "-h") {
      console.log(
        "usage: node scripts/fetch-acurast-deployment-status.mjs --module <name> [--deployment-id <n>] [--network canary|mainnet]"
      );
      process.exit(0);
    }
  }
  if (!out.module) {
    console.error("missing --module");
    process.exit(1);
  }
  return out;
}

function loadMnemonic(moduleDir) {
  const envPath = resolve(moduleDir, ".env");
  if (!existsSync(envPath)) {
    throw new Error(`Missing ${envPath}`);
  }
  const env = readFileSync(envPath, "utf8");
  const match = env.match(/^ACURAST_MNEMONIC=(.+)$/m);
  if (!match) {
    throw new Error(`ACURAST_MNEMONIC not found in ${envPath}`);
  }
  return match[1].trim().replace(/^["']|["']$/g, "");
}

function toPlain(value) {
  if (value == null) return value;
  if (typeof value === "bigint") return value.toString();
  if (typeof value === "object" && typeof value.toString === "function" && value.constructor?.name === "BigNumber") {
    return value.toString();
  }
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map(toPlain);
  if (typeof value === "object") {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = toPlain(v);
    return out;
  }
  return value;
}

function deriveWindowStatus(schedule, nowMs = Date.now()) {
  const start = new Date(schedule.startTime).getTime();
  const end = new Date(schedule.endTime).getTime();
  if (nowMs < start) return "Open";
  if (nowMs <= end) return "Active";
  return "Expired";
}

async function fetchIndexerList(networkCfg, walletAddress) {
  const response = await fetch(networkCfg.indexer, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "API-Key": networkCfg.indexerApiKey,
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      method: "getEvents",
      params: {
        pallet: "Acurast",
        variant: "JobRegistrationStoredV2",
        account_id: walletAddress,
        sort_order: "desc",
      },
      id: 1,
    }),
  });
  const data = await response.json();
  if (data.error) {
    throw new Error(`indexer: ${data.error.message ?? JSON.stringify(data.error)}`);
  }
  return (data.result?.items ?? []).map((item) => ({
    deploymentId: item.data[1],
    registeredAt: item.block_time,
    origin: item.data[0]?.Acurast ?? walletAddress,
  }));
}

async function fetchWalletJobs(acurast, walletAddress) {
  const jobs = await acurast.getAllJobs();
  return jobs
    .filter((job) => job.id[0].acurast === walletAddress)
    .sort((a, b) => b.id[1] - a.id[1]);
}

function formatJobSummary(job, assignments, networkCfg) {
  const schedule = job.registration.schedule;
  const windowStatus = deriveWindowStatus(schedule);
  const acknowledged = assignments.filter((a) => a.assignment?.acknowledged);
  return {
    deploymentId: job.id[1],
    wallet: job.id[0].acurast,
    hubUrl: `https://hub.acurast.com/job-detail/acurast-${job.id[0].acurast}-${job.id[1]}`,
    windowStatus,
    schedule: {
      startTime: schedule.startTime,
      endTime: schedule.endTime,
      durationMs: schedule.duration,
      maxStartDelayMs: schedule.maxStartDelay,
      interval: toPlain(schedule.interval),
    },
    reward: toPlain(job.registration.extra?.requirements?.reward),
    rewardSymbol: networkCfg.symbol,
    slots: job.registration.extra?.requirements?.slots,
    script: job.registration.script,
    assignments: toPlain(assignments),
    acknowledgedProcessors: acknowledged.map((a) => a.processor),
    acknowledgedCount: acknowledged.length,
    totalAssignments: assignments.length,
  };
}

function printHumanSummary(payload) {
  console.log(`Wallet: ${payload.wallet}`);
  if (payload.indexer?.length) {
    console.log(`Indexer registrations (${payload.indexer.length}):`);
    for (const row of payload.indexer.slice(0, 15)) {
      console.log(`  - ${row.deploymentId} (registered ${row.registeredAt})`);
    }
    if (payload.indexer.length > 15) {
      console.log(`  ... and ${payload.indexer.length - 15} more`);
    }
  } else if (payload.indexerError) {
    console.log(`Indexer list: unavailable (${payload.indexerError})`);
  }

  if (!payload.deployment) {
    return;
  }

  const d = payload.deployment;
  console.log("");
  console.log(`Deployment ${d.deploymentId}:`);
  console.log(`  Hub: ${d.hubUrl}`);
  console.log(`  Window: ${d.windowStatus} (${d.schedule.startTime} → ${d.schedule.endTime})`);
  console.log(`  Reward: ${d.reward} ${d.rewardSymbol}, slots: ${d.slots}`);
  console.log(
    `  Processors: ${d.acknowledgedCount}/${d.totalAssignments} acknowledged` +
      (d.acknowledgedProcessors.length ? ` [${d.acknowledgedProcessors.join(", ")}]` : "")
  );
  if (d.assignments?.length) {
    for (const a of d.assignments) {
      console.log(
        `    - ${a.processor}: acknowledged=${a.assignment?.acknowledged}, slot=${a.assignment?.slot}, sla=${a.assignment?.sla?.met}/${a.assignment?.sla?.total}`
      );
    }
  }
}

async function main() {
  const args = parseArgs(process.argv);
  const networkCfg = NETWORK_DEFAULTS[args.network];
  if (!networkCfg) {
    console.error(`unsupported network: ${args.network}`);
    process.exit(1);
  }

  const moduleDir = resolve(`modules/${args.module}`);
  const mnemonic = loadMnemonic(moduleDir);
  const wallet = await walletFromMnemonic(mnemonic, { name: "AcurastCli" });

  const payload = {
    module: args.module,
    network: args.network,
    wallet: wallet.address,
    rpc: networkCfg.rpc,
    indexer: [],
    indexerError: null,
    deployment: null,
  };

  try {
    payload.indexer = await fetchIndexerList(networkCfg, wallet.address);
  } catch (err) {
    payload.indexerError = err instanceof Error ? err.message : String(err);
    console.error(`::warning::Indexer list failed: ${payload.indexerError}`);
  }

  const acurast = new AcurastService(networkCfg.rpc);
  try {
    await acurast.connect();
    if (!acurast.api) {
      throw new Error("RPC API not connected");
    }

    const deploymentNumber = args.deploymentId ? Number(args.deploymentId) : NaN;
    if (!args.deploymentId) {
      if (!payload.indexer.length) {
        const jobs = await fetchWalletJobs(acurast, wallet.address);
        payload.indexer = jobs.map((job) => ({
          deploymentId: job.id[1],
          registeredAt: job.registration.schedule.startTime.toISOString(),
          origin: job.id[0].acurast,
          source: "rpc",
        }));
      }
    } else if (Number.isNaN(deploymentNumber)) {
      throw new Error(`invalid --deployment-id: ${args.deploymentId}`);
    } else {
      const jobs = await fetchWalletJobs(acurast, wallet.address);
      const job = jobs.find((j) => j.id[1] === deploymentNumber);
      if (!job) {
        throw new Error(
          `deployment ${deploymentNumber} not found on-chain for wallet ${wallet.address}`
        );
      }
      const assignments = await getAcknowledgedProcessors(acurast.api, job.id);
      payload.deployment = formatJobSummary(job, assignments, networkCfg);
    }
  } finally {
    await acurast.disconnect();
  }

  printHumanSummary(payload);
  console.log("");
  console.log("--- JSON ---");
  console.log(JSON.stringify(toPlain(payload), null, 2));

  if (process.env.GITHUB_STEP_SUMMARY) {
    const { appendFileSync } = await import("fs");
    const lines = ["## On-chain deployment status", ""];
    if (payload.deployment) {
      const d = payload.deployment;
      lines.push(`- **Deployment:** \`${d.deploymentId}\``);
      lines.push(`- **Window:** ${d.windowStatus}`);
      lines.push(`- **Schedule:** ${d.schedule.startTime} → ${d.schedule.endTime}`);
      lines.push(
        `- **Processors:** ${d.acknowledgedCount}/${d.totalAssignments} acknowledged`
      );
      lines.push(`- **Hub:** ${d.hubUrl}`);
    }
    if (payload.indexer.length) {
      lines.push(`- **Registrations (indexer/RPC):** ${payload.indexer.length}`);
    }
    lines.push("", "```json", JSON.stringify(toPlain(payload), null, 2), "```", "");
    appendFileSync(process.env.GITHUB_STEP_SUMMARY, lines.join("\n"));
  }

  if (args.deploymentId && !payload.deployment) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
