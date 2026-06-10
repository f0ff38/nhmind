import type { Event, EventTemplate } from "nostr-tools";
import {
  SCHEMA_HEARTBEAT,
  SCHEMA_JOB_FEEDBACK,
  SCHEMA_JOB_REQUEST,
  SCHEMA_JOB_RESULT,
} from "./constants";

export type { Event, EventTemplate };

export interface DeploymentId {
  origin: { kind: string; source: string };
  id: string;
}

export interface HealthStatus {
  ok: boolean;
  details?: string;
}

export interface ModuleCapacity {
  max_concurrent_jobs: number;
}

export interface HeartbeatPayload {
  schema: typeof SCHEMA_HEARTBEAT;
  module_id: string;
  deployment_id: DeploymentId;
  health: HealthStatus;
  capacity: ModuleCapacity;
  app_version: string;
  ts: number;
}

export type JobInputEncoding = "plain" | "nip44";
export type JobOutputEncoding = "plain" | "nip44";

export interface JobRequestPayload {
  schema: typeof SCHEMA_JOB_REQUEST;
  job_id: string;
  job_type: string;
  input_encoding: JobInputEncoding;
  input?: unknown;
  ts: number;
}

export type JobResultStatus = "success" | "error" | "processing";

export interface JobResultPayload {
  schema: typeof SCHEMA_JOB_RESULT;
  job_id: string;
  job_type: string;
  output_encoding: JobOutputEncoding;
  output?: unknown;
  ts: number;
}

export type JobFeedbackStatus =
  | "payment-required"
  | "processing"
  | "error"
  | "success";

export interface JobFeedbackPayload {
  schema: typeof SCHEMA_JOB_FEEDBACK;
  job_id: string;
  message?: string;
}
