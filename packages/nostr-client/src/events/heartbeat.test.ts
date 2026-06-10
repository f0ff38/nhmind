import { describe, expect, it } from "vitest";
import { generateSecretKey } from "nostr-tools";
import { NHMIND_CLIENT_TAG, KIND_HEARTBEAT } from "../constants";
import { createPrivateKeySigner } from "../signer";
import {
  buildHeartbeatTemplate,
  heartbeatDTag,
  parseHeartbeatEvent,
} from "./heartbeat";

describe("heartbeat events", () => {
  const deploymentId = {
    origin: { kind: "local", source: "nhmind-dev" },
    id: "0",
  };

  it("builds a NIP-33 heartbeat template", () => {
    const template = buildHeartbeatTemplate({
      moduleId: "hello",
      deploymentId,
      health: { ok: true, details: "relay=ws://nostr-relay:8080" },
      appVersion: "0.1.0",
      createdAt: 1718000000,
    });

    expect(template.kind).toBe(KIND_HEARTBEAT);
    expect(template.created_at).toBe(1718000000);
    expect(template.tags).toEqual([
      ["client", NHMIND_CLIENT_TAG],
      ["d", "heartbeat:hello"],
      ["module", "hello"],
      ["deployment", JSON.stringify(deploymentId)],
    ]);

    const content = JSON.parse(template.content);
    expect(content.schema).toBe("nhmind/heartbeat/v1");
    expect(content.module_id).toBe("hello");
    expect(content.health.ok).toBe(true);
  });

  it("round-trips through sign and parse", () => {
    const signer = createPrivateKeySigner(generateSecretKey());
    const template = buildHeartbeatTemplate({
      moduleId: "hello",
      deploymentId,
      health: { ok: true },
      appVersion: "0.1.0",
      createdAt: 1718000000,
    });
    const signed = signer.signEvent(template);
    const payload = parseHeartbeatEvent(signed);

    expect(payload.module_id).toBe("hello");
    expect(payload.deployment_id).toEqual(deploymentId);
    expect(heartbeatDTag("hello")).toBe("heartbeat:hello");
  });
});
