import { beforeEach, describe, expect, it } from "vitest";
import { createEphemeralSigner } from "../signer";
import { NostrClient } from "../client";
import {
  KIND_REGISTRY,
  KIND_SCORECARD,
  NHMIND_CLIENT_TAG,
} from "../constants";
import { parseRegistryEvent } from "../events/registry";
import { parseScorecardEvent } from "../events/scorecard";
import { resetRelayBackend } from "../transport";

const relayUrl = process.env.RELAY_URL?.trim();
const smokeEnabled = process.env.SMOKE_COORDINATOR_RELAY === "1";
const watchModule = process.env.SMOKE_MODULE?.trim() || "hello";
const coordinatorPubkey = process.env.COORDINATOR_PUBKEY?.trim();
const maxWaitMs = Number(process.env.SMOKE_TIMEOUT_MS ?? "120000");
const maxAgeSec = Number(process.env.SMOKE_MAX_AGE_SEC ?? "180");

const integration = describe.skipIf(!relayUrl || !smokeEnabled);

function assertRecent(createdAt: number, label: string): void {
  const ageSec = Math.floor(Date.now() / 1000) - createdAt;
  expect(ageSec).toBeGreaterThanOrEqual(0);
  expect(ageSec).toBeLessThanOrEqual(maxAgeSec);
}

integration("coordinator-relay integration", () => {
  beforeEach(() => {
    resetRelayBackend();
  });

  it("finds fresh registry and scorecard for watched module", async () => {
    const client = new NostrClient({
      relays: [relayUrl!],
      signer: createEphemeralSigner(),
    });

    const authors = coordinatorPubkey ? [coordinatorPubkey] : undefined;
    const baseFilter = {
      "#client": [NHMIND_CLIENT_TAG],
      "#module": [watchModule],
      ...(authors ? { authors } : {}),
    };

    try {
      const registryEvent = await client.get(
        { kinds: [KIND_REGISTRY], ...baseFilter },
        maxWaitMs,
      );
      expect(registryEvent).not.toBeNull();
      const registry = parseRegistryEvent(registryEvent!);
      expect(registry.module_id).toBe(watchModule);
      expect(registry.schema).toBe("nhmind/registry/v1");
      assertRecent(registryEvent!.created_at, "registry");

      const scorecardEvent = await client.get(
        { kinds: [KIND_SCORECARD], ...baseFilter },
        maxWaitMs,
      );
      expect(scorecardEvent).not.toBeNull();
      const scorecard = parseScorecardEvent(scorecardEvent!);
      expect(scorecard.module_id).toBe(watchModule);
      expect(scorecard.schema).toBe("nhmind/scorecard/v1");
      assertRecent(scorecardEvent!.created_at, "scorecard");

      if (coordinatorPubkey) {
        expect(registryEvent!.pubkey).toBe(coordinatorPubkey);
        expect(scorecardEvent!.pubkey).toBe(coordinatorPubkey);
      }
    } finally {
      await client.close();
    }
  });
});
