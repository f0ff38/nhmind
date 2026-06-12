import { beforeEach, describe, expect, it } from "vitest";
import {
  KIND_JOB_FEEDBACK,
  KIND_JOB_REQUEST,
  NHMIND_CLIENT_TAG,
  buildJobFeedbackTemplate,
  buildJobRequestTemplate,
  buildJobResultTemplate,
  createPrivateKeySigner,
} from "@nhmind/nostr-client";
import { createEphemeralSigner } from "@nhmind/nostr-client";
import { generateSecretKey } from "nostr-tools";
import { loadOracleConfig } from "./config";
import {
  executePaidOracleJob,
  hasExistingJobResult,
  isPaidFeedback,
  parseOracleJobRequest,
  validateBid,
} from "./jobs";
import { RevenueLedger } from "./ledger";
import { createLocalStd } from "../runtime/local-std";

describe("oracle jobs", () => {
  beforeEach(() => {
    globalThis._STD_ = createLocalStd();
  });

  it("parses oracle job request with bid", () => {
    const signer = createEphemeralSigner();
    const template = buildJobRequestTemplate({
      jobId: "job-abc",
      jobType: "oracle",
      workerPubkey: signer.getPublicKey(),
      bidMillisats: "100",
      input: { feed_id: "btc-usd", max_age_sec: 60 },
      createdAt: 1_718_000_000,
    });
    const signed = signer.signEvent(template);
    const job = parseOracleJobRequest(signed);

    expect(job).toMatchObject({
      jobId: "job-abc",
      bidMillisats: 100n,
      input: { feed_id: "btc-usd", max_age_sec: 60 },
    });
  });

  it("detects paid feedback from requester", () => {
    const requester = createPrivateKeySigner(generateSecretKey());
    const job = {
      jobId: "job-abc",
      requesterPubkey: requester.getPublicKey(),
    };
    const template = buildJobFeedbackTemplate({
      jobId: job.jobId,
      status: "paid",
      message: "preimage:deadbeef",
      createdAt: 1_718_000_010,
    });
    const signed = requester.signEvent(template);
    expect(isPaidFeedback(signed, job)).toBe(true);
    expect(isPaidFeedback(signed, { ...job, jobId: "other" })).toBe(false);
  });

  it("rejects paid feedback from non-requester", () => {
    const requester = createPrivateKeySigner(generateSecretKey());
    const impostor = createPrivateKeySigner(generateSecretKey());
    const job = {
      jobId: "job-abc",
      requesterPubkey: requester.getPublicKey(),
    };
    const template = buildJobFeedbackTemplate({
      jobId: job.jobId,
      status: "paid",
      createdAt: 1_718_000_010,
    });
    const signed = impostor.signEvent(template);
    expect(isPaidFeedback(signed, job)).toBe(false);
  });

  it("executes paid job locally and records revenue", async () => {
    const ledger = new RevenueLedger();
    const config = loadOracleConfig();
    const modulePubkey = "cc".repeat(32);

    const result = await executePaidOracleJob(
      {
        jobId: "job-exec",
        requesterPubkey: "dd".repeat(32),
        bidMillisats: 100n,
        input: { feed_id: "btc-usd" },
        requestedAt: 1_718_000_000,
      },
      config,
      ledger,
      modulePubkey,
    );

    expect(result.resultOutput.schema).toBe("nhmind/oracle-result/v1");
    expect(result.quote.feedId).toBe("btc-usd");
    expect(ledger.getMetrics(0, 2_000_000_000, 0n).jobsCompleted).toBe(1);
  });

  it("rejects bid below list price", () => {
    expect(validateBid(50n, 100n)).toBe(false);
    expect(validateBid(100n, 100n)).toBe(true);
  });

  it("ignores non-oracle requests", () => {
    const signer = createEphemeralSigner();
    const template = buildJobRequestTemplate({
      jobId: "echo-1",
      jobType: "echo",
      workerPubkey: signer.getPublicKey(),
      input: { msg: "hi" },
    });
    const signed = signer.signEvent(template);
    expect(parseOracleJobRequest(signed)).toBeNull();
    expect(signed.kind).toBe(KIND_JOB_REQUEST);
    expect(signed.tags[0]).toEqual(["client", NHMIND_CLIENT_TAG]);
  });

  it("detects existing job result on relay", () => {
    const worker = createEphemeralSigner();
    const template = buildJobResultTemplate({
      jobId: "job-done",
      jobType: "oracle",
      requesterPubkey: "aa".repeat(32),
      status: "success",
      output: { value: "67000.00" },
    });
    const signed = worker.signEvent(template);
    expect(
      hasExistingJobResult([signed], "job-done", worker.getPublicKey()),
    ).toBe(true);
    expect(
      hasExistingJobResult([signed], "job-other", worker.getPublicKey()),
    ).toBe(false);
  });

  it("paid feedback kind is 7000", () => {
    expect(KIND_JOB_FEEDBACK).toBe(7000);
  });
});
