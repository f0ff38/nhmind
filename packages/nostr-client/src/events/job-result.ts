import { KIND_JOB_RESULT, SCHEMA_JOB_RESULT } from "../constants";
import { decryptPayload, encryptPayload } from "../nip44";
import type {
  Event,
  EventTemplate,
  JobResultPayload,
  JobResultStatus,
} from "../types";
import {
  clientTag,
  compactJson,
  parseJsonContent,
  requireTagValue,
} from "./common";

export interface BuildJobResultParams {
  jobId: string;
  jobType: string;
  requesterPubkey: string;
  status: JobResultStatus;
  output?: unknown;
  outputEncoding?: JobResultPayload["output_encoding"];
  createdAt?: number;
  senderPrivateKey?: Uint8Array;
}

export interface DecryptJobResultParams {
  recipientPrivateKey: Uint8Array;
  senderPublicKey: string;
}

export function buildJobResultPayload(
  params: BuildJobResultParams,
): JobResultPayload {
  const createdAt = params.createdAt ?? Math.floor(Date.now() / 1000);
  const outputEncoding = params.outputEncoding ?? "plain";

  if (outputEncoding === "nip44") {
    return {
      schema: SCHEMA_JOB_RESULT,
      job_id: params.jobId,
      job_type: params.jobType,
      output_encoding: outputEncoding,
      ts: createdAt,
    };
  }

  return {
    schema: SCHEMA_JOB_RESULT,
    job_id: params.jobId,
    job_type: params.jobType,
    output_encoding: outputEncoding,
    output: params.output,
    ts: createdAt,
  };
}

export function buildJobResultTemplate(
  params: BuildJobResultParams,
): EventTemplate {
  const createdAt = params.createdAt ?? Math.floor(Date.now() / 1000);
  const outputEncoding = params.outputEncoding ?? "plain";
  const payload = buildJobResultPayload({ ...params, createdAt });

  const tags: string[][] = [
    clientTag(),
    ["request", params.jobId],
    ["p", params.requesterPubkey],
    ["status", params.status],
  ];

  let content: string;
  if (outputEncoding === "nip44") {
    if (!params.senderPrivateKey) {
      throw new Error("senderPrivateKey is required for nip44 job results");
    }
    if (params.output === undefined) {
      throw new Error("output is required for nip44 job results");
    }
    const secretPayload = compactJson({
      schema: SCHEMA_JOB_RESULT,
      job_id: params.jobId,
      job_type: params.jobType,
      output_encoding: outputEncoding,
      output: params.output,
      ts: createdAt,
    });
    content = encryptPayload(
      params.senderPrivateKey,
      params.requesterPubkey,
      secretPayload,
    );
  } else {
    content = compactJson(payload);
  }

  return {
    kind: KIND_JOB_RESULT,
    created_at: createdAt,
    tags,
    content,
  };
}

export function parseJobResultEvent(
  event: Event,
  decrypt?: DecryptJobResultParams,
): JobResultPayload {
  if (event.kind !== KIND_JOB_RESULT) {
    throw new Error(`expected kind ${KIND_JOB_RESULT}, got ${event.kind}`);
  }

  const jobId = requireTagValue(event.tags, "request");
  const requesterPubkey = requireTagValue(event.tags, "p");
  requireTagValue(event.tags, "status");

  const looksEncrypted = !event.content.trimStart().startsWith("{");
  if (looksEncrypted) {
    if (!decrypt) {
      throw new Error("encrypted job result requires decrypt params");
    }
    const plaintext = decryptPayload(
      decrypt.recipientPrivateKey,
      decrypt.senderPublicKey,
      event.content,
    );
    const payload = parseJsonContent<JobResultPayload>(plaintext);
    validateJobResultPayload(payload, jobId, requesterPubkey);
    return payload;
  }

  const payload = parseJsonContent<JobResultPayload>(event.content);
  if (payload.output_encoding === "nip44" && payload.output !== undefined) {
    throw new Error("nip44 payload must not include plaintext output");
  }
  validateJobResultPayload(payload, jobId, requesterPubkey);
  return payload;
}

function validateJobResultPayload(
  payload: JobResultPayload,
  jobId: string,
  requesterPubkey: string,
): void {
  if (payload.schema !== SCHEMA_JOB_RESULT) {
    throw new Error(`unexpected schema: ${payload.schema}`);
  }
  if (payload.job_id !== jobId) {
    throw new Error("request tag does not match payload.job_id");
  }
  if (!requesterPubkey) {
    throw new Error("missing requester pubkey tag");
  }
}
