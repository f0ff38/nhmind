import { millisatsToRevenueAcu } from "./config";

export interface SettledJob {
  jobId: string;
  requesterPubkey: string;
  feedId: string;
  settledMsats: bigint;
  revenueAcu: bigint;
  settledAt: number;
  latencyMs: number;
}

export interface OracleModuleMetrics {
  revenueAcu: bigint;
  costAcu: bigint;
  jobsCompleted: number;
  jobsRejected: number;
  avgLatencyMs: number;
  windowStart: number;
  windowEnd: number;
}

export class RevenueLedger {
  private readonly settled = new Map<string, SettledJob>();
  private rejected = 0;

  recordSettled(job: SettledJob): void {
    if (this.settled.has(job.jobId)) {
      return;
    }
    this.settled.set(job.jobId, job);
  }

  recordRejected(): void {
    this.rejected += 1;
  }

  getMetrics(
    windowStart: number,
    windowEnd: number,
    costAcu: bigint,
  ): OracleModuleMetrics {
    const jobs = [...this.settled.values()].filter(
      (job) => job.settledAt >= windowStart && job.settledAt < windowEnd,
    );

    let revenueAcu = 0n;
    let latencyTotal = 0;
    for (const job of jobs) {
      revenueAcu += job.revenueAcu;
      latencyTotal += job.latencyMs;
    }

    return {
      revenueAcu,
      costAcu,
      jobsCompleted: jobs.length,
      jobsRejected: this.rejected,
      avgLatencyMs:
        jobs.length > 0 ? Math.round(latencyTotal / jobs.length) : 0,
      windowStart,
      windowEnd,
    };
  }
}

export function settleJob(
  params: {
    jobId: string;
    requesterPubkey: string;
    feedId: string;
    settledMsats: bigint;
    msatToAcuRate: bigint;
    settledAt: number;
    latencyMs: number;
  },
  ledger: RevenueLedger,
): SettledJob {
  const revenueAcu = millisatsToRevenueAcu(
    params.settledMsats,
    params.msatToAcuRate,
  );
  const job: SettledJob = {
    jobId: params.jobId,
    requesterPubkey: params.requesterPubkey,
    feedId: params.feedId,
    settledMsats: params.settledMsats,
    revenueAcu,
    settledAt: params.settledAt,
    latencyMs: params.latencyMs,
  };
  ledger.recordSettled(job);
  return job;
}
