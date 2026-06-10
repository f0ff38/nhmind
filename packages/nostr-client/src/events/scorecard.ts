import {
  KIND_SCORECARD,
  SCHEMA_SCORECARD,
} from "../constants";
import type { Event, EventTemplate } from "../types";
import type { DeploymentId, ScorecardPayload, Verdict } from "../types";
import {
  clientTag,
  compactJson,
  getTagValue,
  parseJsonContent,
  requireTagValue,
} from "./common";

export interface BuildScorecardParams {
  moduleId: string;
  deploymentId: DeploymentId;
  windowStart: number;
  windowEnd: number;
  revenueAcu: string;
  costAcu: string;
  relayFeesAcu: string;
  roi: number;
  verdict: Verdict;
  verdictReason?: string;
  createdAt?: number;
}

export function scorecardDTag(moduleId: string): string {
  return `scorecard:${moduleId}`;
}

export function buildScorecardPayload(
  params: BuildScorecardParams,
): ScorecardPayload {
  const createdAt = params.createdAt ?? Math.floor(Date.now() / 1000);
  return {
    schema: SCHEMA_SCORECARD,
    module_id: params.moduleId,
    deployment_id: params.deploymentId,
    window_start: params.windowStart,
    window_end: params.windowEnd,
    revenue_acu: params.revenueAcu,
    cost_acu: params.costAcu,
    relay_fees_acu: params.relayFeesAcu,
    roi: params.roi,
    verdict: params.verdict,
    verdict_reason: params.verdictReason,
    ts: createdAt,
  };
}

export function buildScorecardTemplate(
  params: BuildScorecardParams,
): EventTemplate {
  const createdAt = params.createdAt ?? Math.floor(Date.now() / 1000);
  const payload = buildScorecardPayload({ ...params, createdAt });

  return {
    kind: KIND_SCORECARD,
    created_at: createdAt,
    tags: [
      clientTag(),
      ["d", scorecardDTag(params.moduleId)],
      ["module", params.moduleId],
      ["deployment", compactJson(params.deploymentId)],
    ],
    content: compactJson(payload),
  };
}

export function parseScorecardEvent(event: Event): ScorecardPayload {
  if (event.kind !== KIND_SCORECARD) {
    throw new Error(`expected kind ${KIND_SCORECARD}, got ${event.kind}`);
  }

  const moduleId = requireTagValue(event.tags, "module");
  const dTag = requireTagValue(event.tags, "d");
  if (dTag !== scorecardDTag(moduleId)) {
    throw new Error(`invalid scorecard d tag: ${dTag}`);
  }

  const payload = parseJsonContent<ScorecardPayload>(event.content);
  if (payload.schema !== SCHEMA_SCORECARD) {
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
