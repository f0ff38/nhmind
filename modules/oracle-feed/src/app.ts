import {
  KIND_JOB_FEEDBACK,
  KIND_JOB_REQUEST,
  KIND_JOB_RESULT,
  NostrClient,
  buildHeartbeatTemplate,
  buildJobResultTemplate,
  whitelistRelayHost,
} from "@nhmind/nostr-client";
import type { Event } from "@nhmind/nostr-client";
import {
  JOB_TYPE_ORACLE,
  MODULE_ID,
  SCHEMA_ORACLE_RESULT,
  loadOracleConfig,
} from "./oracle/config";
import { SUPPORTED_FEEDS, whitelistPriceApiHosts } from "./oracle/feeds";
import {
  executePaidOracleJob,
  hasExistingJobResult,
  isPaidFeedback,
  parseOracleJobRequest,
} from "./oracle/jobs";
import { RevenueLedger } from "./oracle/ledger";
import { createBusinessModule, healthCheck } from "./module";
import { createModuleSigner } from "./runtime/nostr-signer";
import { getStd } from "./runtime/types";

const ledger = new RevenueLedger();
const processedJobs = new Set<string>();

export { healthCheck, ledger, createBusinessModule };

export function resetOracleRuntimeState(): void {
  processedJobs.clear();
}

function httpGetAdapter(
  url: string,
  headers: Record<string, string>,
): Promise<string> {
  return new Promise((resolve, reject) => {
    httpGET(
      url,
      headers,
      (payload) => resolve(payload),
      (message) => reject(new Error(message)),
    );
  });
}

function buildPricingHeartbeatContent(
  templateContent: string,
  listPriceMsats: bigint,
  msatToAcuRate: bigint,
): string {
  const payload = JSON.parse(templateContent) as Record<string, unknown>;
  payload.pricing = {
    feeds: Object.values(SUPPORTED_FEEDS).map((feed) => ({
      feed_id: feed.feedId,
      price_msats: listPriceMsats.toString(),
    })),
    msat_to_acu_rate: msatToAcuRate.toString(),
    job_type: JOB_TYPE_ORACLE,
  };
  return JSON.stringify(payload);
}

export async function publishHeartbeat(): Promise<boolean> {
  const std = getStd();
  const relayUrl = std.env.RELAY_URL?.trim();
  if (!relayUrl) {
    return false;
  }

  const config = loadOracleConfig();
  const health = healthCheck();
  let client: NostrClient | undefined;

  try {
    whitelistRelayHost(std.network, relayUrl);
    client = new NostrClient({
      relays: [relayUrl],
      signer: createModuleSigner(),
    });

    const template = buildHeartbeatTemplate({
      moduleId: MODULE_ID,
      deploymentId: std.job.getId(),
      health,
      capacity: { max_concurrent_jobs: 4 },
      appVersion: std.app_info.version,
    });
    template.content = buildPricingHeartbeatContent(
      template.content,
      config.listPriceMsats,
      config.msatToAcuRate,
    );

    const event = await client.publish(template);
    console.log("heartbeat published:", event.id);
    return true;
  } catch (error) {
    console.warn(
      "heartbeat publish skipped:",
      error instanceof Error ? error.message : String(error),
    );
    return false;
  } finally {
    if (client) {
      await client.close();
    }
  }
}

async function fetchRecentEvents(
  client: NostrClient,
  kinds: number[],
  since: number,
): Promise<Event[]> {
  const events: Event[] = [];
  const seen = new Set<string>();

  await new Promise<void>((resolve) => {
    const timeout = setTimeout(() => {
      unsubscribe();
      resolve();
    }, 3_000);

    const unsubscribe = client.subscribe(
      [{ kinds, since, "#client": ["nhmind"] }],
      {
        onevent: (event) => {
          if (seen.has(event.id)) {
            return;
          }
          seen.add(event.id);
          events.push(event);
        },
        oneose: () => {
          clearTimeout(timeout);
          unsubscribe();
          resolve();
        },
      },
    );
  });

  return events.sort((a, b) => a.created_at - b.created_at);
}

export async function processOracleJobs(): Promise<number> {
  const std = getStd();
  const relayUrl = std.env.RELAY_URL?.trim();
  if (!relayUrl) {
    return 0;
  }

  const config = loadOracleConfig();
  const health = healthCheck();
  if (!health.ok) {
    throw new Error(health.details ?? "health check failed");
  }

  let client: NostrClient | undefined;
  let completed = 0;

  try {
    whitelistRelayHost(std.network, relayUrl);
    whitelistPriceApiHosts(std.network);
    client = new NostrClient({
      relays: [relayUrl],
      signer: createModuleSigner(),
    });

    const modulePubkey = client.publicKey;
    const since =
      Math.floor(Date.now() / 1000) - config.jobLookbackSec;

    const requests = (
      await fetchRecentEvents(client, [KIND_JOB_REQUEST], since)
    ).filter((event) =>
      event.tags.some((tag) => tag[0] === "p" && tag[1] === modulePubkey),
    );

    const feedback = await fetchRecentEvents(
      client,
      [KIND_JOB_FEEDBACK],
      since,
    );

    const results = await fetchRecentEvents(client, [KIND_JOB_RESULT], since);

    for (const event of requests) {
      const job = parseOracleJobRequest(event);
      if (!job || processedJobs.has(job.jobId)) {
        continue;
      }

      if (hasExistingJobResult(results, job.jobId, modulePubkey)) {
        processedJobs.add(job.jobId);
        continue;
      }

      const paid = feedback.some((fb) => isPaidFeedback(fb, job));
      if (!paid) {
        continue;
      }

      try {
        const { resultOutput } = await executePaidOracleJob(
          job,
          config,
          ledger,
          modulePubkey,
          httpGetAdapter,
        );

        await client.publish(
          buildJobResultTemplate({
            jobId: job.jobId,
            jobType: JOB_TYPE_ORACLE,
            requesterPubkey: job.requesterPubkey,
            status: "success",
            output: resultOutput,
          }),
        );

        processedJobs.add(job.jobId);
        completed += 1;
        console.log("oracle job completed:", job.jobId, resultOutput.value);
      } catch (error) {
        const message =
          error instanceof Error ? error.message : String(error);
        console.warn("oracle job failed:", job.jobId, message);

        await client.publish(
          buildJobResultTemplate({
            jobId: job.jobId,
            jobType: JOB_TYPE_ORACLE,
            requesterPubkey: job.requesterPubkey,
            status: "error",
            output: {
              schema: SCHEMA_ORACLE_RESULT,
              job_id: job.jobId,
              message,
            },
          }),
        );
        processedJobs.add(job.jobId);
      }
    }

    return completed;
  } finally {
    if (client) {
      await client.close();
    }
  }
}

export async function main(): Promise<void> {
  const std = getStd();
  const health = healthCheck();

  console.log("NostrHiveMind oracle-feed module");
  console.log("deployment:", JSON.stringify(std.job.getId()));
  console.log("device:", std.device.getAddress());
  console.log("health:", JSON.stringify(health));

  if (!health.ok) {
    throw new Error(health.details ?? "health check failed");
  }

  const completed = await processOracleJobs();
  const metrics = await createBusinessModule({ ledger }).getMetrics();
  console.log("jobs completed this run:", completed);
  console.log("metrics:", JSON.stringify(metrics, replacerBigInt));

  await publishHeartbeat();
}

function replacerBigInt(_key: string, value: unknown): unknown {
  return typeof value === "bigint" ? value.toString() : value;
}
