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

export async function main(): Promise<void> {
  const std = getStd();
  const deployment = std.job.getId();
  const health = healthCheck();

  console.log("NostrHiveMind template module");
  console.log("deployment:", JSON.stringify(deployment));
  console.log("device:", std.device.getAddress());
  console.log("health:", JSON.stringify(health));

  if (!health.ok) {
    throw new Error(health.details ?? "health check failed");
  }
}
