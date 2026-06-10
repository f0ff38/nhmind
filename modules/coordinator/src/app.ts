import { NostrClient } from "@nhmind/nostr-client";
import {
  parseWatchModules,
  runCoordinatorCycle,
  type CoordinatorConfig,
} from "./coordinator/cycle";
import { createDeployActions } from "./deploy/actions";
import { createCoordinatorSigner } from "./runtime/nostr-signer";
import { getStd } from "./runtime/types";

export interface HealthCheckResult {
  ok: boolean;
  details?: string;
}

export function healthCheck(): HealthCheckResult {
  const std = getStd();
  const relayUrl = std.env.RELAY_URL?.trim();

  if (!relayUrl) {
    return { ok: false, details: "RELAY_URL is not configured" };
  }

  return {
    ok: true,
    details: `relay=${relayUrl}, watch=${std.env.COORDINATOR_WATCH_MODULES ?? "hello"}`,
  };
}

export function buildCoordinatorConfig(): CoordinatorConfig {
  const std = getStd();
  const relayUrl = std.env.RELAY_URL?.trim() ?? "";

  return {
    relayUrl,
    watchModules: parseWatchModules(std.env.COORDINATOR_WATCH_MODULES),
    network: std.job.getId().origin.source === "nhmind-dev" ? "local" : "canary",
    coordinatorDeploymentId: std.job.getId(),
  };
}

export async function runCycle(): Promise<void> {
  const std = getStd();
  const health = healthCheck();
  if (!health.ok) {
    throw new Error(health.details ?? "health check failed");
  }

  const config = buildCoordinatorConfig();
  let client: NostrClient | undefined;

  try {
    client = new NostrClient({
      relays: [config.relayUrl],
      signer: createCoordinatorSigner(),
    });

    const result = await runCoordinatorCycle({
      client,
      deploy: createDeployActions(std.env),
      config,
    });

    console.log("coordinator cycle complete:", JSON.stringify(result));
  } finally {
    if (client) {
      await client.close();
    }
  }
}

export async function main(): Promise<void> {
  const std = getStd();
  const deployment = std.job.getId();
  const health = healthCheck();

  console.log("NostrHiveMind coordinator");
  console.log("deployment:", JSON.stringify(deployment));
  console.log("device:", std.device.getAddress());
  console.log("health:", JSON.stringify(health));

  if (!health.ok) {
    throw new Error(health.details ?? "health check failed");
  }

  await runCycle();
}
