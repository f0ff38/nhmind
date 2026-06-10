import type { Verdict } from "@nhmind/nostr-client";
import type { RegisteredModule } from "./registry";

export interface VerdictDecision {
  verdict: Verdict;
  reason: string;
}

const STUB_OBSERVATION_REASON =
  "stub metrics: observation window (Phase 2)";

export function computeVerdict(module: RegisteredModule): VerdictDecision {
  if (!module.heartbeat.health.ok) {
    return {
      verdict: "pause",
      reason: `health check failed: ${module.heartbeat.health.details ?? "unknown"}`,
    };
  }

  return {
    verdict: "pause",
    reason: STUB_OBSERVATION_REASON,
  };
}
