import { describe, expect, it } from "vitest";
import { RevenueLedger, settleJob } from "./ledger";

describe("revenue ledger", () => {
  it("aggregates settled jobs in window", () => {
    const ledger = new RevenueLedger();
    const now = 1_718_000_000;

    settleJob(
      {
        jobId: "job-1",
        requesterPubkey: "aa".repeat(32),
        feedId: "btc-usd",
        settledMsats: 100n,
        msatToAcuRate: 10n,
        settledAt: now,
        latencyMs: 120,
      },
      ledger,
    );

    const metrics = ledger.getMetrics(now - 10, now + 10, 50_000n);
    expect(metrics.jobsCompleted).toBe(1);
    expect(metrics.revenueAcu).toBe(1000n);
    expect(metrics.costAcu).toBe(50_000n);
    expect(metrics.avgLatencyMs).toBe(120);
  });

  it("deduplicates job_id", () => {
    const ledger = new RevenueLedger();
    const now = 1_718_000_000;
    const params = {
      jobId: "job-dup",
      requesterPubkey: "bb".repeat(32),
      feedId: "eth-usd",
      settledMsats: 100n,
      msatToAcuRate: 10n,
      settledAt: now,
      latencyMs: 50,
    };

    settleJob(params, ledger);
    settleJob(params, ledger);

    expect(ledger.getMetrics(now - 1, now + 1, 0n).jobsCompleted).toBe(1);
  });
});
