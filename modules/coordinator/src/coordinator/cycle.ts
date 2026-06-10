import {
  KIND_HEARTBEAT,
  NHMIND_CLIENT_TAG,
  buildRegistryTemplate,
  buildScorecardTemplate,
  parseHeartbeatEvent,
  type DeploymentId,
  type NostrClient,
} from "@nhmind/nostr-client";
import type { DeployActions } from "../deploy/actions";
import { ModuleRegistry, registryStatusForVerdict } from "./registry";
import { buildStubScorecard } from "./scorecard";
import { computeVerdict } from "./verdict";

const OBSERVATION_WINDOW_SEC = 7 * 24 * 60 * 60;

export interface CoordinatorConfig {
  relayUrl: string;
  watchModules: string[];
  network: string;
  coordinatorDeploymentId: DeploymentId;
}

export interface ModuleCycleResult {
  moduleId: string;
  registered: boolean;
  verdict: string;
  registryPublished: boolean;
  scorecardPublished: boolean;
}

export interface CycleResult {
  modules: ModuleCycleResult[];
}

export interface CoordinatorDeps {
  client: NostrClient;
  deploy: DeployActions;
  config: CoordinatorConfig;
  now?: () => number;
}

export async function runCoordinatorCycle(
  deps: CoordinatorDeps,
): Promise<CycleResult> {
  const nowSec = deps.now ?? (() => Math.floor(Date.now() / 1000));
  const now = nowSec();
  const registry = new ModuleRegistry();
  const results: ModuleCycleResult[] = [];

  for (const moduleId of deps.config.watchModules) {
    const heartbeatEvent = await deps.client.get({
      kinds: [KIND_HEARTBEAT],
      "#client": [NHMIND_CLIENT_TAG],
      "#module": [moduleId],
    });

    if (!heartbeatEvent) {
      results.push({
        moduleId,
        registered: false,
        verdict: "none",
        registryPublished: false,
        scorecardPublished: false,
      });
      continue;
    }

    const heartbeat = parseHeartbeatEvent(heartbeatEvent);
    const registered = registry.registerFromHeartbeat(
      heartbeat,
      heartbeatEvent.pubkey,
      now,
    );

    const decision = computeVerdict(registered);
    await deps.deploy.applyVerdict(
      registered.moduleId,
      decision.verdict,
      registered.deploymentId,
    );

    const windowEnd = now;
    const windowStart = windowEnd - OBSERVATION_WINDOW_SEC;
    const scorecardPayload = buildStubScorecard({
      module: registered,
      verdict: decision.verdict,
      verdictReason: decision.reason,
      windowStart,
      windowEnd,
    });

    const registryStatus = registryStatusForVerdict(decision.verdict);

    let registryPublished = false;
    let scorecardPublished = false;

    try {
      const registryEvent = await deps.client.publish(
        buildRegistryTemplate({
          moduleId: registered.moduleId,
          deploymentId: registered.deploymentId,
          modulePubkey: registered.modulePubkey,
          network: deps.config.network,
          registeredAt: registered.registeredAt,
          status: registryStatus,
          createdAt: now,
        }),
      );
      registryPublished = true;
      console.log("registry published:", registryEvent.id, registered.moduleId);
    } catch (error) {
      console.warn(
        `registry publish failed for ${registered.moduleId}:`,
        error instanceof Error ? error.message : String(error),
      );
    }

    try {
      const scorecardEvent = await deps.client.publish(
        buildScorecardTemplate({
          moduleId: scorecardPayload.module_id,
          deploymentId: scorecardPayload.deployment_id,
          windowStart: scorecardPayload.window_start,
          windowEnd: scorecardPayload.window_end,
          revenueAcu: scorecardPayload.revenue_acu,
          costAcu: scorecardPayload.cost_acu,
          relayFeesAcu: scorecardPayload.relay_fees_acu,
          roi: scorecardPayload.roi,
          verdict: scorecardPayload.verdict,
          verdictReason: scorecardPayload.verdict_reason,
          createdAt: now,
        }),
      );
      scorecardPublished = true;
      console.log("scorecard published:", scorecardEvent.id, registered.moduleId);
    } catch (error) {
      console.warn(
        `scorecard publish failed for ${registered.moduleId}:`,
        error instanceof Error ? error.message : String(error),
      );
    }

    results.push({
      moduleId: registered.moduleId,
      registered: true,
      verdict: decision.verdict,
      registryPublished,
      scorecardPublished,
    });
  }

  return { modules: results };
}

export function parseWatchModules(raw: string | undefined): string[] {
  if (!raw?.trim()) {
    return ["hello"];
  }
  return raw
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
}
