import { KIND_JOB_FEEDBACK, SCHEMA_JOB_FEEDBACK } from "../constants";
import type {
  Event,
  EventTemplate,
  JobFeedbackPayload,
  JobFeedbackStatus,
} from "../types";
import {
  clientTag,
  compactJson,
  parseJsonContent,
  requireTagValue,
} from "./common";

export interface BuildJobFeedbackParams {
  jobId: string;
  status: JobFeedbackStatus;
  message?: string;
  createdAt?: number;
}

export function buildJobFeedbackPayload(
  params: BuildJobFeedbackParams,
): JobFeedbackPayload {
  return {
    schema: SCHEMA_JOB_FEEDBACK,
    job_id: params.jobId,
    message: params.message,
  };
}

export function buildJobFeedbackTemplate(
  params: BuildJobFeedbackParams,
): EventTemplate {
  const createdAt = params.createdAt ?? Math.floor(Date.now() / 1000);
  const payload = buildJobFeedbackPayload(params);

  return {
    kind: KIND_JOB_FEEDBACK,
    created_at: createdAt,
    tags: [
      clientTag(),
      ["request", params.jobId],
      ["status", params.status],
    ],
    content: compactJson(payload),
  };
}

export function parseJobFeedbackEvent(event: Event): JobFeedbackPayload {
  if (event.kind !== KIND_JOB_FEEDBACK) {
    throw new Error(`expected kind ${KIND_JOB_FEEDBACK}, got ${event.kind}`);
  }

  const jobId = requireTagValue(event.tags, "request");
  const status = requireTagValue(event.tags, "status");

  const payload = parseJsonContent<JobFeedbackPayload>(event.content);
  if (payload.schema !== SCHEMA_JOB_FEEDBACK) {
    throw new Error(`unexpected schema: ${payload.schema}`);
  }
  if (payload.job_id !== jobId) {
    throw new Error("request tag does not match payload.job_id");
  }
  if (!status) {
    throw new Error("missing feedback status tag");
  }

  return payload;
}
