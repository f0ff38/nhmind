import { getStd } from "../runtime/types";

export const MODULE_ID = "oracle-feed";
export const JOB_TYPE_ORACLE = "oracle";
export const SCHEMA_ORACLE_RESULT = "nhmind/oracle-result/v1";

export const DEFAULT_LIST_PRICE_MSATS = 100n;
export const DEFAULT_MSAT_TO_ACU_RATE = 10n;
export const DEFAULT_JOB_LOOKBACK_SEC = 3600;
export const METRICS_WINDOW_SEC = 7 * 24 * 3600;

export interface OracleConfig {
  listPriceMsats: bigint;
  msatToAcuRate: bigint;
  jobLookbackSec: number;
}

export function loadOracleConfig(): OracleConfig {
  const std = getStd();
  return {
    listPriceMsats: parsePositiveBigInt(
      std.env.ORACLE_LIST_PRICE_MSATS,
      DEFAULT_LIST_PRICE_MSATS,
    ),
    msatToAcuRate: parsePositiveBigInt(
      std.env.ORACLE_MSAT_TO_ACU_RATE,
      DEFAULT_MSAT_TO_ACU_RATE,
    ),
    jobLookbackSec: parsePositiveInt(
      std.env.ORACLE_JOB_LOOKBACK_SEC,
      DEFAULT_JOB_LOOKBACK_SEC,
    ),
  };
}

function parsePositiveBigInt(
  raw: string | undefined,
  fallback: bigint,
): bigint {
  if (!raw?.trim()) {
    return fallback;
  }
  try {
    const value = BigInt(raw.trim());
    return value > 0n ? value : fallback;
  } catch {
    return fallback;
  }
}

function parsePositiveInt(raw: string | undefined, fallback: number): number {
  if (!raw?.trim()) {
    return fallback;
  }
  const value = Number.parseInt(raw.trim(), 10);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

export function millisatsToRevenueAcu(
  millisats: bigint,
  rate: bigint,
): bigint {
  return millisats * rate;
}
