import type { Event } from "@nhmind/nostr-client";
import {
  JOB_TYPE_ORACLE,
  SCHEMA_ORACLE_RESULT,
  type OracleConfig,
} from "./config";
import type { HttpGetFn, OracleQuote } from "./feeds";
import { fetchOracleQuote, mockOracleQuote } from "./feeds";
import type { RevenueLedger } from "./ledger";
import { settleJob } from "./ledger";
import { getStd, isAcurastProcessor } from "../runtime/types";

export interface OracleJobInput {
  feed_id: string;
  max_age_sec?: number;
}

export interface PendingOracleJob {
  jobId: string;
  requesterPubkey: string;
  bidMillisats: bigint;
  input: OracleJobInput;
  requestedAt: number;
}

function tagValue(tags: string[][], name: string): string | undefined {
  return tags.find(([key]) => key === name)?.[1];
}

export function parseBidMillisats(event: Event): bigint | undefined {
  const raw = tagValue(event.tags, "bid");
  if (!raw?.trim()) {
    return undefined;
  }
  try {
    const value = BigInt(raw.trim());
    return value > 0n ? value : undefined;
  } catch {
    return undefined;
  }
}

export function parseOracleJobRequest(event: Event): PendingOracleJob | null {
  const jobType = tagValue(event.tags, "job_type");
  if (jobType !== JOB_TYPE_ORACLE) {
    return null;
  }

  const jobId = tagValue(event.tags, "d");
  if (!jobId) {
    return null;
  }

  let payload: { input?: OracleJobInput };
  try {
    payload = JSON.parse(event.content) as { input?: OracleJobInput };
  } catch {
    return null;
  }

  const feedId = payload.input?.feed_id?.trim();
  if (!feedId) {
    return null;
  }

  const bidMillisats = parseBidMillisats(event);
  if (!bidMillisats) {
    return null;
  }

  return {
    jobId,
    requesterPubkey: event.pubkey,
    bidMillisats,
    input: {
      feed_id: feedId,
      max_age_sec: payload.input?.max_age_sec,
    },
    requestedAt: event.created_at,
  };
}

export function isPaidFeedback(event: Event, jobId: string): boolean {
  if (event.kind !== 7000) {
    return false;
  }
  const request = tagValue(event.tags, "request");
  const status = tagValue(event.tags, "status");
  return request === jobId && status === "paid";
}

export function validateBid(
  bidMillisats: bigint,
  listPriceMsats: bigint,
): boolean {
  return bidMillisats >= listPriceMsats;
}

export function buildOracleResultOutput(
  quote: OracleQuote,
  jobId: string,
  settledMsats: bigint,
  modulePubkey: string,
  attestation: { processor: string; signature: string },
): Record<string, unknown> {
  return {
    schema: SCHEMA_ORACLE_RESULT,
    job_id: jobId,
    feed_id: quote.feedId,
    value: quote.value,
    source_fetched_at: quote.fetchedAt,
    sources_used: quote.sourcesUsed,
    module_id: "oracle-feed",
    module_pubkey: modulePubkey,
    settled_msats: settledMsats.toString(),
    attestation,
    ts: quote.fetchedAt,
  };
}

export async function resolveOracleQuote(
  input: OracleJobInput,
  httpGet?: HttpGetFn,
): Promise<OracleQuote> {
  const maxAgeSec = input.max_age_sec ?? 60;

  if (!isAcurastProcessor()) {
    return mockOracleQuote(input.feed_id, [67000.12, 67010.5, 66995.0]);
  }

  if (!httpGet) {
    throw new Error("httpGET adapter is required on Acurast processor");
  }

  return fetchOracleQuote(input.feed_id, maxAgeSec, httpGet);
}

export interface ExecutedOracleJob {
  quote: OracleQuote;
  resultOutput: Record<string, unknown>;
}

export async function executePaidOracleJob(
  job: PendingOracleJob,
  config: OracleConfig,
  ledger: RevenueLedger,
  modulePubkey: string,
  httpGet?: HttpGetFn,
  nowSec = Math.floor(Date.now() / 1000),
): Promise<ExecutedOracleJob> {
  if (!validateBid(job.bidMillisats, config.listPriceMsats)) {
    ledger.recordRejected();
    throw new Error(
      `bid ${job.bidMillisats} below list price ${config.listPriceMsats}`,
    );
  }

  const started = Date.now();
  const quote = await resolveOracleQuote(job.input, httpGet);
  const latencyMs = Date.now() - started;

  const std = getStd();
  const payloadHex = Buffer.from(
    JSON.stringify({ job_id: job.jobId, value: quote.value }),
    "utf8",
  ).toString("hex");
  const signature = std.signers.secp256k1.sign(payloadHex);

  settleJob(
    {
      jobId: job.jobId,
      requesterPubkey: job.requesterPubkey,
      feedId: job.input.feed_id,
      settledMsats: job.bidMillisats,
      msatToAcuRate: config.msatToAcuRate,
      settledAt: nowSec,
      latencyMs,
    },
    ledger,
  );

  const resultOutput = buildOracleResultOutput(
    quote,
    job.jobId,
    job.bidMillisats,
    modulePubkey,
    {
      processor: std.device.getAddress(),
      signature,
    },
  );

  return { quote, resultOutput };
}
