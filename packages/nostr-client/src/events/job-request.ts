import { KIND_JOB_REQUEST, SCHEMA_JOB_REQUEST } from "../constants";
import { decryptPayload, encryptPayload } from "../nip44";
import type { Event, EventTemplate, JobRequestPayload } from "../types";
import {
  clientTag,
  compactJson,
  parseJsonContent,
  requireTagValue,
} from "./common";

export interface BuildJobRequestParams {
  jobId: string;
  jobType: string;
  workerPubkey: string;
  input?: unknown;
  inputEncoding?: JobRequestPayload["input_encoding"];
  bidMillisats?: string;
  capabilityTags?: string[];
  createdAt?: number;
  senderPrivateKey?: Uint8Array;
}

export interface DecryptJobRequestParams {
  recipientPrivateKey: Uint8Array;
  senderPublicKey: string;
}

export function buildJobRequestPayload(
  params: BuildJobRequestParams,
): JobRequestPayload {
  const createdAt = params.createdAt ?? Math.floor(Date.now() / 1000);
  const inputEncoding = params.inputEncoding ?? "plain";

  if (inputEncoding === "nip44") {
    return {
      schema: SCHEMA_JOB_REQUEST,
      job_id: params.jobId,
      job_type: params.jobType,
      input_encoding: inputEncoding,
      ts: createdAt,
    };
  }

  return {
    schema: SCHEMA_JOB_REQUEST,
    job_id: params.jobId,
    job_type: params.jobType,
    input_encoding: inputEncoding,
    input: params.input,
    ts: createdAt,
  };
}

export function buildJobRequestTemplate(
  params: BuildJobRequestParams,
): EventTemplate {
  const createdAt = params.createdAt ?? Math.floor(Date.now() / 1000);
  const inputEncoding = params.inputEncoding ?? "plain";
  const payload = buildJobRequestPayload({ ...params, createdAt });

  const tags: string[][] = [
    clientTag(),
    ["d", params.jobId],
    ["p", params.workerPubkey],
    ["job_type", params.jobType],
  ];

  if (params.bidMillisats) {
    tags.push(["bid", params.bidMillisats]);
  }

  for (const capability of params.capabilityTags ?? []) {
    tags.push(["t", capability]);
  }

  let content: string;
  if (inputEncoding === "nip44") {
    if (!params.senderPrivateKey) {
      throw new Error("senderPrivateKey is required for nip44 job requests");
    }
    if (params.input === undefined) {
      throw new Error("input is required for nip44 job requests");
    }
    const secretPayload = compactJson({
      schema: SCHEMA_JOB_REQUEST,
      job_id: params.jobId,
      job_type: params.jobType,
      input_encoding: inputEncoding,
      input: params.input,
      ts: createdAt,
    });
    content = encryptPayload(
      params.senderPrivateKey,
      params.workerPubkey,
      secretPayload,
    );
  } else {
    content = compactJson(payload);
  }

  return {
    kind: KIND_JOB_REQUEST,
    created_at: createdAt,
    tags,
    content,
  };
}

export function parseJobRequestEvent(
  event: Event,
  decrypt?: DecryptJobRequestParams,
): JobRequestPayload {
  if (event.kind !== KIND_JOB_REQUEST) {
    throw new Error(`expected kind ${KIND_JOB_REQUEST}, got ${event.kind}`);
  }

  const jobId = requireTagValue(event.tags, "d");
  const workerPubkey = requireTagValue(event.tags, "p");
  const jobType = requireTagValue(event.tags, "job_type");

  const looksEncrypted = !event.content.trimStart().startsWith("{");
  if (looksEncrypted) {
    if (!decrypt) {
      throw new Error("encrypted job request requires decrypt params");
    }
    const plaintext = decryptPayload(
      decrypt.recipientPrivateKey,
      decrypt.senderPublicKey,
      event.content,
    );
    const payload = parseJsonContent<JobRequestPayload>(plaintext);
    validateJobRequestPayload(payload, jobId, jobType, workerPubkey);
    return payload;
  }

  const payload = parseJsonContent<JobRequestPayload>(event.content);
  if (payload.input_encoding === "nip44" && payload.input !== undefined) {
    throw new Error("nip44 payload must not include plaintext input");
  }
  validateJobRequestPayload(payload, jobId, jobType, workerPubkey);
  return payload;
}

function validateJobRequestPayload(
  payload: JobRequestPayload,
  jobId: string,
  jobType: string,
  workerPubkey: string,
): void {
  if (payload.schema !== SCHEMA_JOB_REQUEST) {
    throw new Error(`unexpected schema: ${payload.schema}`);
  }
  if (payload.job_id !== jobId) {
    throw new Error("d tag does not match payload.job_id");
  }
  if (payload.job_type !== jobType) {
    throw new Error("job_type tag does not match payload.job_type");
  }
  if (!workerPubkey) {
    throw new Error("missing worker pubkey tag");
  }
}
