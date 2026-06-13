import { beforeEach, describe, expect, it } from "vitest";
import { createBusinessModule, healthCheck, ledger, resetOracleRuntimeState } from "./app";
import { createLocalStd } from "./runtime/local-std";

describe("oracle-feed app", () => {
  beforeEach(() => {
    resetOracleRuntimeState();
    globalThis._STD_ = createLocalStd({ RELAY_URL: "ws://nostr-relay:8080" });
  });

  it("passes health check with relay configured", () => {
    expect(healthCheck().ok).toBe(true);
    expect(healthCheck().details).toContain("oracle-feed");
  });

  it("fails health check without relay", () => {
    globalThis._STD_ = createLocalStd({ RELAY_URL: "" });
    expect(healthCheck().ok).toBe(false);
  });

  it("exposes getMetrics via IBusinessModule", async () => {
    const metrics = await createBusinessModule({ ledger }).getMetrics();
    expect(metrics.jobsCompleted).toBe(0);
    expect(metrics.revenueAcu).toBe(0n);
  });
});
