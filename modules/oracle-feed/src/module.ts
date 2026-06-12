import {
  METRICS_WINDOW_SEC,
  loadOracleConfig,
  MODULE_ID,
  type OracleConfig,
} from "./oracle/config";
import type { OracleModuleMetrics, RevenueLedger } from "./oracle/ledger";
import { getStd } from "./runtime/types";

export interface HealthCheckResult {
  ok: boolean;
  details?: string;
}

export interface IBusinessModule {
  healthCheck(): HealthCheckResult;
  getMetrics(): Promise<OracleModuleMetrics>;
}

export function healthCheck(): HealthCheckResult {
  const std = getStd();
  const relayUrl = std.env.RELAY_URL?.trim();

  if (!relayUrl) {
    return { ok: false, details: "RELAY_URL is not configured" };
  }

  return {
    ok: true,
    details: `module=${MODULE_ID}, relay=${relayUrl}, version=${std.app_info.version}`,
  };
}

export function createBusinessModule(deps: {
  ledger: RevenueLedger;
  config?: OracleConfig;
  costAcu?: bigint;
}): IBusinessModule {
  const config = deps.config ?? loadOracleConfig();

  return {
    healthCheck,
    async getMetrics() {
      const windowEnd = Math.floor(Date.now() / 1000);
      const windowStart = windowEnd - METRICS_WINDOW_SEC;
      return deps.ledger.getMetrics(
        windowStart,
        windowEnd,
        deps.costAcu ?? 0n,
      );
    },
  };
}
