import {
  SCHEMA_SCORECARD,
  type ScorecardPayload,
  type Verdict,
} from "@nhmind/nostr-client";
import type { RegisteredModule } from "./registry";

export interface StubScorecardParams {
  module: RegisteredModule;
  verdict: Verdict;
  verdictReason: string;
  windowStart: number;
  windowEnd: number;
}

export function buildStubScorecard(
  params: StubScorecardParams,
): ScorecardPayload {
  const { module, verdict, verdictReason, windowStart, windowEnd } = params;

  return {
    schema: SCHEMA_SCORECARD,
    module_id: module.moduleId,
    deployment_id: module.deploymentId,
    window_start: windowStart,
    window_end: windowEnd,
    revenue_acu: "0",
    cost_acu: "0",
    relay_fees_acu: "0",
    roi: 0,
    verdict,
    verdict_reason: verdictReason,
    ts: windowEnd,
  };
}
