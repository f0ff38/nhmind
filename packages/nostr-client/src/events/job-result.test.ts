import { describe, expect, it } from "vitest";
import { generateSecretKey, getPublicKey } from "nostr-tools";
import { KIND_JOB_RESULT, NHMIND_CLIENT_TAG } from "../constants";
import { createPrivateKeySigner } from "../signer";
import {
  buildJobResultTemplate,
  parseJobResultEvent,
} from "./job-result";

describe("job result events", () => {
  const requesterPubkey =
    "03bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

  it("builds a NIP-90 job result template", () => {
    const template = buildJobResultTemplate({
      jobId: "job-1",
      jobType: "echo",
      requesterPubkey,
      status: "success",
      output: { message: "pong" },
      createdAt: 1718000060,
    });

    expect(template.kind).toBe(KIND_JOB_RESULT);
    expect(template.tags).toEqual([
      ["client", NHMIND_CLIENT_TAG],
      ["request", "job-1"],
      ["p", requesterPubkey],
      ["status", "success"],
    ]);

    const content = JSON.parse(template.content);
    expect(content.schema).toBe("nhmind/job-result/v1");
    expect(content.output).toEqual({ message: "pong" });
  });

  it("round-trips encrypted nip44 output", () => {
    const worker = generateSecretKey();
    const requester = generateSecretKey();
    const requesterPubkey = getPublicKey(requester);

    const template = buildJobResultTemplate({
      jobId: "job-1",
      jobType: "echo",
      requesterPubkey,
      status: "success",
      output: { message: "pong" },
      outputEncoding: "nip44",
      senderPrivateKey: worker,
      createdAt: 1718000060,
    });

    const signed = createPrivateKeySigner(worker).signEvent(template);
    const payload = parseJobResultEvent(signed, {
      recipientPrivateKey: requester,
      senderPublicKey: getPublicKey(worker),
    });

    expect(payload.output_encoding).toBe("nip44");
    expect(payload.output).toEqual({ message: "pong" });
  });
});
