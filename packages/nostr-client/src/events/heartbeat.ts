import {
  KIND_HEARTBEAT,
  SCHEMA_HEARTBEAT,
} from "../constants";
import type { Event, EventTemplate } from "../types";
import type {
  DeploymentId,
  HealthStatus,
  HeartbeatPayload,
  ModuleCapacity,
} from "../types";
import {
  clientTag,
  compactJson,
  getTagValue,
  parseJsonContent,
  requireTagValue,
} from "./common";

export interface BuildHeartbeatParams {
  moduleId: string;
  deploymentId: DeploymentId;
  health: HealthStatus;
  capacity?: ModuleCapacity;
  appVersion: string;
  createdAt?: number;
}

export function heartbeatDTag(moduleId: string): string {
  return `heartbeat:${moduleId}`;
}

export function buildHeartbeatPayload(
  params: BuildHeartbeatParams,
): HeartbeatPayload {
  const createdAt = params.createdAt ?? Math.floor(Date.now() / 1000);
  return {
    schema: SCHEMA_HEARTBEAT,
    module_id: params.moduleId,
    deployment_id: params.deploymentId,
    health: params.health,
    capacity: params.capacity ?? { max_concurrent_jobs: 1 },
    app_version: params.appVersion,
    ts: createdAt,
  };
}

export function buildHeartbeatTemplate(
  params: BuildHeartbeatParams,
): EventTemplate {
  const createdAt = params.createdAt ?? Math.floor(Date.now() / 1000);
  const payload = buildHeartbeatPayload({ ...params, createdAt });

  return {
    kind: KIND_HEARTBEAT,
    created_at: createdAt,
    tags: [
      clientTag(),
      ["d", heartbeatDTag(params.moduleId)],
      ["module", params.moduleId],
      ["deployment", compactJson(params.deploymentId)],
    ],
    content: compactJson(payload),
  };
}

export function parseHeartbeatEvent(event: Event): HeartbeatPayload {
  if (event.kind !== KIND_HEARTBEAT) {
    throw new Error(`expected kind ${KIND_HEARTBEAT}, got ${event.kind}`);
  }

  const moduleId = requireTagValue(event.tags, "module");
  const dTag = requireTagValue(event.tags, "d");
  if (dTag !== heartbeatDTag(moduleId)) {
    throw new Error(`invalid heartbeat d tag: ${dTag}`);
  }

  const payload = parseJsonContent<HeartbeatPayload>(event.content);
  if (payload.schema !== SCHEMA_HEARTBEAT) {
    throw new Error(`unexpected schema: ${payload.schema}`);
  }
  if (payload.module_id !== moduleId) {
    throw new Error("module tag does not match payload.module_id");
  }

  const deploymentTag = getTagValue(event.tags, "deployment");
  if (deploymentTag && deploymentTag !== compactJson(payload.deployment_id)) {
    throw new Error("deployment tag does not match payload.deployment_id");
  }

  return payload;
}
