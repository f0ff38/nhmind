import type {
  DeploymentId,
  HeartbeatPayload,
  RegistryStatus,
} from "@nhmind/nostr-client";

export interface RegisteredModule {
  moduleId: string;
  deploymentId: DeploymentId;
  modulePubkey: string;
  heartbeat: HeartbeatPayload;
  registeredAt: number;
  lastSeenAt: number;
}

export class ModuleRegistry {
  private readonly modules = new Map<string, RegisteredModule>();

  registerFromHeartbeat(
    heartbeat: HeartbeatPayload,
    modulePubkey: string,
    now: number,
  ): RegisteredModule {
    const existing = this.modules.get(heartbeat.module_id);
    const registeredAt = existing?.registeredAt ?? now;

    const entry: RegisteredModule = {
      moduleId: heartbeat.module_id,
      deploymentId: heartbeat.deployment_id,
      modulePubkey,
      heartbeat,
      registeredAt,
      lastSeenAt: now,
    };

    this.modules.set(heartbeat.module_id, entry);
    return entry;
  }

  get(moduleId: string): RegisteredModule | undefined {
    return this.modules.get(moduleId);
  }

  list(): RegisteredModule[] {
    return [...this.modules.values()];
  }
}

export function registryStatusForVerdict(
  verdict: "promote" | "pause" | "kill",
): RegistryStatus {
  switch (verdict) {
    case "promote":
      return "active";
    case "pause":
      return "paused";
    case "kill":
      return "killed";
  }
}
