import { describe, expect, it } from "vitest";
import type { RegisteredModule } from "./registry";
import { computeVerdict } from "./verdict";

function moduleWithHealth(ok: boolean, details?: string): RegisteredModule {
  return {
    moduleId: "hello",
    deploymentId: {
      origin: { kind: "local", source: "nhmind-dev" },
      id: "0",
    },
    modulePubkey: "02" + "a".repeat(62),
    heartbeat: {
      schema: "nhmind/heartbeat/v1",
      module_id: "hello",
      deployment_id: {
        origin: { kind: "local", source: "nhmind-dev" },
        id: "0",
      },
      health: { ok, details },
      capacity: { max_concurrent_jobs: 1 },
      app_version: "0.1.0",
      ts: 1718000000,
    },
    registeredAt: 1718000000,
    lastSeenAt: 1718000000,
  };
}

describe("computeVerdict", () => {
  it("pauses when health check failed", () => {
    const decision = computeVerdict(
      moduleWithHealth(false, "RELAY_URL is not configured"),
    );
    expect(decision.verdict).toBe("pause");
    expect(decision.reason).toContain("health check failed");
  });

  it("pauses healthy modules with stub metrics in Phase 2", () => {
    const decision = computeVerdict(moduleWithHealth(true));
    expect(decision.verdict).toBe("pause");
    expect(decision.reason).toContain("stub metrics");
  });
});
