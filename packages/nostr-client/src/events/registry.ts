import {
  KIND_REGISTRY,
  SCHEMA_REGISTRY,
} from "../constants";
import type { Event, EventTemplate } from "../types";
import type { DeploymentId, RegistryPayload, RegistryStatus } from "../types";
import {
  clientTag,
  compactJson,
  getTagValue,
  parseJsonContent,
  requireTagValue,
} from "./common";

export interface BuildRegistryParams {
  moduleId: string;
  deploymentId: DeploymentId;
  modulePubkey: string;
  network: string;
  registeredAt: number;
  status: RegistryStatus;
  createdAt?: number;
}

export function registryDTag(moduleId: string): string {
  return `registry:${moduleId}`;
}

export function buildRegistryPayload(
  params: BuildRegistryParams,
): RegistryPayload {
  const createdAt = params.createdAt ?? Math.floor(Date.now() / 1000);
  return {
    schema: SCHEMA_REGISTRY,
    module_id: params.moduleId,
    deployment_id: params.deploymentId,
    module_pubkey: params.modulePubkey,
    network: params.network,
    registered_at: params.registeredAt,
    status: params.status,
  };
}

export function buildRegistryTemplate(
  params: BuildRegistryParams,
): EventTemplate {
  const createdAt = params.createdAt ?? Math.floor(Date.now() / 1000);
  const payload = buildRegistryPayload({ ...params, createdAt });

  return {
    kind: KIND_REGISTRY,
    created_at: createdAt,
    tags: [
      clientTag(),
      ["d", registryDTag(params.moduleId)],
      ["module", params.moduleId],
      ["deployment", compactJson(params.deploymentId)],
    ],
    content: compactJson(payload),
  };
}

export function parseRegistryEvent(event: Event): RegistryPayload {
  if (event.kind !== KIND_REGISTRY) {
    throw new Error(`expected kind ${KIND_REGISTRY}, got ${event.kind}`);
  }

  const moduleId = requireTagValue(event.tags, "module");
  const dTag = requireTagValue(event.tags, "d");
  if (dTag !== registryDTag(moduleId)) {
    throw new Error(`invalid registry d tag: ${dTag}`);
  }

  const payload = parseJsonContent<RegistryPayload>(event.content);
  if (payload.schema !== SCHEMA_REGISTRY) {
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
