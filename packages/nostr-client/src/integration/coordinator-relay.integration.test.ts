import { beforeEach, describe, expect, it } from "vitest";
import { createEphemeralSigner } from "../signer";
import { NostrClient } from "../client";
import {
  KIND_HEARTBEAT,
  KIND_REGISTRY,
  KIND_SCORECARD,
  NHMIND_CLIENT_TAG,
} from "../constants";
import { parseRegistryEvent } from "../events/registry";
import { parseScorecardEvent } from "../events/scorecard";
import { resetRelayBackend } from "../transport";

const relayUrl = process.env.RELAY_URL?.trim();
const smokeEnabled = process.env.SMOKE_COORDINATOR_RELAY === "1";
const preflightHeartbeat = process.env.SMOKE_PREFLIGHT_HEARTBEAT === "1";
const watchModule = process.env.SMOKE_MODULE?.trim() || "hello";
const coordinatorPubkey = process.env.COORDINATOR_PUBKEY?.trim();
const maxWaitMs = Number(process.env.SMOKE_TIMEOUT_MS ?? "120000");
const maxAgeSec = Number(process.env.SMOKE_MAX_AGE_SEC ?? "180");

const integration = describe.skipIf(!relayUrl || !smokeEnabled);

async function waitForEvent(
  client: NostrClient,
  filter: Parameters<NostrClient["get"]>[0],
  timeoutMs: number,
  label: string,
): Promise<NonNullable<Awaited<ReturnType<NostrClient["get"]>>>> {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const event = await client.get(filter, 5_000);
    if (event) {
      return event;
    }
    await new Promise((resolve) => setTimeout(resolve, 2_000));
  }
  throw new Error(
    `timed out after ${timeoutMs}ms waiting for ${label} on ${relayUrl}`,
  );
}

function assertRecent(createdAt: number, label: string): void {
  const ageSec = Math.floor(Date.now() / 1000) - createdAt;
  expect(ageSec).toBeGreaterThanOrEqual(0);
  expect(ageSec).toBeLessThanOrEqual(maxAgeSec);
}

integration("coordinator-relay integration", () => {
  beforeEach(() => {
    resetRelayBackend();
  });

  it.skipIf(!preflightHeartbeat)(
    "preflight finds hello heartbeat on relay",
    async () => {
      const client = new NostrClient({
        relays: [relayUrl!],
        signer: createEphemeralSigner(),
      });

      try {
        const heartbeatEvent = await waitForEvent(
          client,
          {
            kinds: [KIND_HEARTBEAT],
            "#client": [NHMIND_CLIENT_TAG],
            "#module": [watchModule],
          },
          maxWaitMs,
          `heartbeat kind ${KIND_HEARTBEAT} (#module=${watchModule})`,
        );
        assertRecent(heartbeatEvent!.created_at, "heartbeat");
      } finally {
        await client.close();
      }
    },
  );

  it.skipIf(preflightHeartbeat)(
    "finds fresh registry and scorecard for watched module",
    async () => {
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
        const heartbeatEvent = await client.get(
          {
            kinds: [KIND_HEARTBEAT],
            ...baseFilter,
          },
          5_000,
        );
        if (!heartbeatEvent) {
          throw new Error(
            `no hello heartbeat (kind ${KIND_HEARTBEAT}, #module=${watchModule}) on ${relayUrl}; redeploy hello with maxNetworkRequests>0, _acu TXT, and whitelist`,
          );
        }

        const registryEvent = await waitForEvent(
          client,
          { kinds: [KIND_REGISTRY], ...baseFilter },
          maxWaitMs,
          `registry kind ${KIND_REGISTRY}`,
        );
        const registry = parseRegistryEvent(registryEvent!);
        expect(registry.module_id).toBe(watchModule);
        expect(registry.schema).toBe("nhmind/registry/v1");
        assertRecent(registryEvent!.created_at, "registry");

        const scorecardEvent = await waitForEvent(
          client,
          { kinds: [KIND_SCORECARD], ...baseFilter },
          maxWaitMs,
          `scorecard kind ${KIND_SCORECARD}`,
        );
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
    },
  );
});
