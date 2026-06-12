import {
  NostrClient,
  buildHeartbeatTemplate,
  whitelistRelayHost,
} from "@nhmind/nostr-client";
import { createModuleSigner } from "./runtime/nostr-signer";
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
    details: `relay=${relayUrl}, version=${std.app_info.version}`,
  };
}

export async function publishHeartbeat(): Promise<boolean> {
  const std = getStd();
  const relayUrl = std.env.RELAY_URL?.trim();
  if (!relayUrl) {
    return false;
  }

  const health = healthCheck();
  let client: NostrClient | undefined;

  try {
    whitelistRelayHost(std.network, relayUrl);
    client = new NostrClient({
      relays: [relayUrl],
      signer: createModuleSigner(),
    });
    const event = await client.publish(
      buildHeartbeatTemplate({
        moduleId: "hello",
        deploymentId: std.job.getId(),
        health,
        appVersion: std.app_info.version,
      }),
    );
    console.log("heartbeat published:", event.id);
    return true;
  } catch (error) {
    console.warn(
      "heartbeat publish skipped:",
      error instanceof Error ? error.message : String(error),
    );
    return false;
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

  console.log("NostrHiveMind hello module");
  console.log("deployment:", JSON.stringify(deployment));
  console.log("device:", std.device.getAddress());
  console.log("health:", JSON.stringify(health));

  if (!health.ok) {
    throw new Error(health.details ?? "health check failed");
  }

  await publishHeartbeat();
}
