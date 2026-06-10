import { describe, expect, it } from "vitest";
import { generateSecretKey, getPublicKey } from "nostr-tools";
import { NHMIND_CLIENT_TAG, KIND_JOB_REQUEST } from "../constants";
import { createPrivateKeySigner } from "../signer";
import {
  buildJobRequestTemplate,
  parseJobRequestEvent,
} from "./job-request";

describe("job request events", () => {
  const workerPubkey =
    "03aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

  it("builds a NIP-90 job request template", () => {
    const template = buildJobRequestTemplate({
      jobId: "a1b2c3d4e5f6",
      jobType: "echo",
      workerPubkey,
      input: { message: "ping" },
      capabilityTags: ["test"],
      createdAt: 1718000000,
    });

    expect(template.kind).toBe(KIND_JOB_REQUEST);
    expect(template.tags).toEqual([
      ["client", NHMIND_CLIENT_TAG],
      ["d", "a1b2c3d4e5f6"],
      ["p", workerPubkey],
      ["job_type", "echo"],
      ["t", "test"],
    ]);

    const content = JSON.parse(template.content);
    expect(content.schema).toBe("nhmind/job-request/v1");
    expect(content.input).toEqual({ message: "ping" });
    expect(content.input_encoding).toBe("plain");
  });

  it("round-trips through sign and parse", () => {
    const signer = createPrivateKeySigner(generateSecretKey());
    const template = buildJobRequestTemplate({
      jobId: "job-1",
      jobType: "echo",
      workerPubkey,
      input: { message: "ping" },
      createdAt: 1718000000,
    });
    const signed = signer.signEvent(template);
    const payload = parseJobRequestEvent(signed);

    expect(payload.job_id).toBe("job-1");
    expect(payload.job_type).toBe("echo");
    expect(payload.input).toEqual({ message: "ping" });
  });

  it("encrypts nip44 input in content", () => {
    const sender = generateSecretKey();
    const worker = generateSecretKey();
    const workerPubkey = getPublicKey(worker);

    const template = buildJobRequestTemplate({
      jobId: "secret-job",
      jobType: "echo",
      workerPubkey,
      input: { token: "secret" },
      inputEncoding: "nip44",
      senderPrivateKey: sender,
      createdAt: 1718000000,
    });

    expect(template.content.startsWith("{")).toBe(false);

    const signed = createPrivateKeySigner(sender).signEvent(template);
    const payload = parseJobRequestEvent(signed, {
      recipientPrivateKey: worker,
      senderPublicKey: getPublicKey(sender),
    });

    expect(payload.input_encoding).toBe("nip44");
    expect(payload.input).toEqual({ token: "secret" });
  });
});
