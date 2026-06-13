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

const cliRoot =
  process.env.ACURAST_CLI_ROOT ?? "/usr/local/lib/node_modules/@acurast/cli";
const sdkRoot =
  process.env.ACURAST_SDK_ROOT ?? `${cliRoot}/node_modules/@acurast/sdk/dist`;
const polkadotApiPath =
  process.env.POLKADOT_API_PATH ?? `${cliRoot}/node_modules/@polkadot/api/index.js`;

const { ApiPromise, WsProvider } = await import(pathToFileURL(polkadotApiPath).href);
const { walletFromMnemonic, getAcknowledgedProcessors } = await import(
  pathToFileURL(`${sdkRoot}/chain/index.js`).href
);
const { CUSTOM_TYPES } = await import(pathToFileURL(`${sdkRoot}/types/env.js`).href);

const CANARY_RPC_CANDIDATES = [
  process.env.ACURAST_CANARY_RPC,
  process.env.ACURAST_RPC,
  "wss://public-rpc.canary.acurast.com",
  "wss://canarynet-ws-1.acurast-h-server-2.papers.tech",
].filter(Boolean);

const NETWORK_DEFAULTS = {
  canary: {
    rpcCandidates: CANARY_RPC_CANDIDATES,
    indexer:
      process.env.ACURAST_CANARY_INDEXER ??
      "https://dev.indexer.canary.acurast.com/api/v1/rpc",
    indexerApiKey:
      process.env.ACURAST_CANARY_INDEXER_API_KEY ?? "OXuwySHqNSlwwa_qqB-cBw",
    symbol: "cACU",
  },
  mainnet: {
    rpcCandidates: [
      process.env.ACURAST_MAINNET_RPC,
      process.env.ACURAST_RPC,
      "wss://public-rpc.mainnet.acurast.com",
      "wss://archive.mainnet.acurast.com",
    ].filter(Boolean),
    indexer:
      process.env.ACURAST_MAINNET_INDEXER ??
      "https://dev.indexer.mainnet.acurast.com/api/v1/rpc",
    indexerApiKey:
      process.env.ACURAST_MAINNET_INDEXER_API_KEY ?? "HbLxqSJoPTnzwa_rkF-tYv",
    symbol: "ACU",
  },
};

const RPC_TIMEOUT_MS = Number(process.env.ACURAST_RPC_TIMEOUT_MS ?? "120000");

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
  if (
    typeof value === "object" &&
    typeof value.toString === "function" &&
    value.constructor?.name === "BigNumber"
  ) {
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

function decodeScript(script) {
  if (typeof script !== "string") return script;
  if (!script.startsWith("0x")) return script;
  return new TextDecoder().decode(Buffer.from(script.slice(2), "hex"));
}

function registrationFromJson(json) {
  const schedule = json.schedule ?? {};
  return {
    script: decodeScript(json.script),
    schedule: {
      duration: Number(schedule.duration ?? 0),
      startTime: new Date(Number(schedule.startTime ?? 0)),
      endTime: new Date(Number(schedule.endTime ?? 0)),
      interval: schedule.interval ?? "0",
      maxStartDelay: Number(schedule.maxStartDelay ?? 0),
    },
    extra: {
      requirements: {
        slots: Number(json.extra?.requirements?.slots ?? 0),
        reward: json.extra?.requirements?.reward ?? "0",
      },
    },
  };
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

async function connectApi(rpcEndpoint) {
  const apiAugmentPath = `${cliRoot}/node_modules/@polkadot/api-augment/index.js`;
  await import(pathToFileURL(apiAugmentPath).href);
  const provider = new WsProvider(rpcEndpoint, 2500, {}, RPC_TIMEOUT_MS);
  const api = await ApiPromise.create({
    provider,
    noInitWarn: true,
    types: { ...CUSTOM_TYPES },
  });
  return { api, provider };
}

async function connectWithFallback(rpcCandidates) {
  let lastError = null;
  for (const rpc of rpcCandidates) {
    try {
      console.log(`Connecting RPC: ${rpc}`);
      const conn = await connectApi(rpc);
      return { ...conn, rpc };
    } catch (err) {
      lastError = err;
      console.error(`::warning::RPC ${rpc} failed: ${err instanceof Error ? err.message : err}`);
    }
  }
  throw lastError ?? new Error("no RPC endpoints configured");
}

async function fetchAssignedProcessorAddresses(api, deploymentNumber) {
  const entries = await api.query.acurastMarketplace.assignedProcessors.entries(
    deploymentNumber
  );
  return entries.map(([key]) => key.args[1].toString());
}

async function fetchJobById(api, walletAddress, deploymentNumber) {
  const origin = api.createType("AcurastCommonMultiOrigin", { Acurast: walletAddress });
  const id = api.createType("u128", deploymentNumber);
  const opt = await api.query.acurast.storedJobRegistration(origin, id);
  if (opt.isNone) {
    return null;
  }
  const json = opt.unwrap().toJSON();
  return {
    id: [{ acurast: walletAddress }, deploymentNumber],
    registration: registrationFromJson(json),
  };
}

function formatJobSummary(job, assignments, assignedProcessorAddresses, networkCfg) {
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
    assignedProcessorAddresses,
    assignments: toPlain(assignments),
    acknowledgedProcessors: acknowledged.map((a) => a.processor),
    acknowledgedCount: acknowledged.length,
    totalAssignments: assignments.length,
    storedMatchCount: assignments.length,
  };
}

function printHumanSummary(payload) {
  console.log(`Wallet: ${payload.wallet}`);
  console.log(`RPC used: ${payload.rpc ?? "n/a"}`);
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
  if (d.assignedProcessorAddresses?.length) {
    console.log(`  Assigned (marketplace): ${d.assignedProcessorAddresses.join(", ")}`);
  }
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
    rpc: null,
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

  const { api, provider, rpc } = await connectWithFallback(networkCfg.rpcCandidates);
  payload.rpc = rpc;

  try {
    const deploymentNumber = args.deploymentId ? Number(args.deploymentId) : NaN;

    if (!args.deploymentId) {
      if (!payload.indexer.length) {
        console.log(
          "::notice::Indexer unavailable and list-only mode skips full-chain scan; pass --deployment-id"
        );
      }
    } else if (Number.isNaN(deploymentNumber)) {
      throw new Error(`invalid --deployment-id: ${args.deploymentId}`);
    } else {
      const job = await fetchJobById(api, wallet.address, deploymentNumber);
      if (!job) {
        throw new Error(
          `deployment ${deploymentNumber} not found on-chain for wallet ${wallet.address}`
        );
      }
      const [assignments, assignedProcessorAddresses] = await Promise.all([
        getAcknowledgedProcessors(api, job.id),
        fetchAssignedProcessorAddresses(api, deploymentNumber),
      ]);
      payload.deployment = formatJobSummary(
        job,
        assignments,
        assignedProcessorAddresses,
        networkCfg
      );
    }
  } finally {
    await api.disconnect();
    await provider.disconnect();
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
      lines.push(`- **Registrations (indexer):** ${payload.indexer.length}`);
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
