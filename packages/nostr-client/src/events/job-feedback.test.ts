import { describe, expect, it } from "vitest";
import { generateSecretKey } from "nostr-tools";
import { KIND_JOB_FEEDBACK, NHMIND_CLIENT_TAG } from "../constants";
import { createPrivateKeySigner } from "../signer";
import {
  buildJobFeedbackTemplate,
  parseJobFeedbackEvent,
} from "./job-feedback";

describe("job feedback events", () => {
  it("builds a NIP-90 feedback template", () => {
    const template = buildJobFeedbackTemplate({
      jobId: "job-1",
      status: "processing",
      message: "working",
      createdAt: 1718000030,
    });

    expect(template.kind).toBe(KIND_JOB_FEEDBACK);
    expect(template.tags).toEqual([
      ["client", NHMIND_CLIENT_TAG],
      ["request", "job-1"],
      ["status", "processing"],
    ]);

    const content = JSON.parse(template.content);
    expect(content.schema).toBe("nhmind/job-feedback/v1");
    expect(content.message).toBe("working");
  });

  it("supports paid settlement status", () => {
    const template = buildJobFeedbackTemplate({
      jobId: "job-paid",
      status: "paid",
      message: "preimage:abc123",
      createdAt: 1718000035,
    });
    expect(template.tags).toContainEqual(["status", "paid"]);
  });

  it("round-trips through sign and parse", () => {
    const signer = createPrivateKeySigner(generateSecretKey());
    const template = buildJobFeedbackTemplate({
      jobId: "job-1",
      status: "success",
      createdAt: 1718000040,
    });
    const signed = signer.signEvent(template);
    const payload = parseJobFeedbackEvent(signed);

    expect(payload.job_id).toBe("job-1");
  });
});
