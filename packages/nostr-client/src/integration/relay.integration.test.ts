import { beforeEach, describe, expect, it } from "vitest";
import { generateSecretKey } from "nostr-tools";
import { NostrClient } from "../client";
import { KIND_HEARTBEAT } from "../constants";
import {
  buildHeartbeatTemplate,
  heartbeatDTag,
  parseHeartbeatEvent,
} from "../events/heartbeat";
import { createPrivateKeySigner } from "../signer";
import { resetRelayBackend } from "../transport";

const relayUrl = process.env.RELAY_URL?.trim();
const integration = describe.skipIf(!relayUrl);

async function waitFor<T>(
  factory: () => Promise<T | null | undefined>,
  timeoutMs = 15_000,
): Promise<T> {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const value = await factory();
    if (value) {
      return value;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error("timed out waiting for condition");
}

integration("nostr-relay integration", () => {
  beforeEach(() => {
    resetRelayBackend();
  });

  it("publishes and reads back a replaceable heartbeat", async () => {
    const signer = createPrivateKeySigner(generateSecretKey());
    const client = new NostrClient({
      relays: [relayUrl!],
      signer,
    });

    const deploymentId = {
      origin: { kind: "integration", source: "nhmind-test" },
      id: "1",
    };

    const filter = {
      kinds: [KIND_HEARTBEAT],
      authors: [signer.getPublicKey()],
      "#d": [heartbeatDTag("hello")],
    };

    try {
      const published = await client.publish(
        buildHeartbeatTemplate({
          moduleId: "hello",
          deploymentId,
          health: { ok: true, details: "integration" },
          appVersion: "0.1.0",
        }),
      );

      const stored = await waitFor(() => client.get(filter, 2_000));
      const payload = parseHeartbeatEvent(stored!);

      expect(payload.module_id).toBe("hello");
      expect(payload.deployment_id).toEqual(deploymentId);
      expect(published.id).toBe(stored!.id);
    } finally {
      await client.close();
    }
  });
});
