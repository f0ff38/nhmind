import { beforeEach, describe, expect, it } from "vitest";
import { generateSecretKey } from "nostr-tools";
import { NostrClient } from "./client";
import { resetRelayBackend } from "./transport";
import { buildHeartbeatTemplate } from "./events/heartbeat";
import { createPrivateKeySigner } from "./signer";

describe("NostrClient", () => {
  beforeEach(() => {
    resetRelayBackend();
  });
  it("signs events without publishing when only sign() is used", () => {
    const signer = createPrivateKeySigner(generateSecretKey());
    const client = new NostrClient({
      relays: ["ws://nostr-relay:8080"],
      signer,
    });

    const event = client.sign(
      buildHeartbeatTemplate({
        moduleId: "hello",
        deploymentId: {
          origin: { kind: "local", source: "nhmind-dev" },
          id: "0",
        },
        health: { ok: true },
        appVersion: "0.1.0",
        createdAt: 1718000000,
      }),
    );

    expect(event.pubkey).toBe(signer.getPublicKey());
    expect(event.sig).toMatch(/^[0-9a-f]{128}$/);
    expect(event.id).toMatch(/^[0-9a-f]{64}$/);
  });

  it("requires at least one relay", () => {
    const signer = createPrivateKeySigner(generateSecretKey());
    expect(
      () =>
        new NostrClient({
          relays: [],
          signer,
        }),
    ).toThrow("at least one relay URL is required");
  });
});
