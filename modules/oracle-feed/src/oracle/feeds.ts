export interface FeedDefinition {
  feedId: string;
  sources: readonly string[];
  maxAgeSec: number;
}

export const SUPPORTED_FEEDS: Record<string, FeedDefinition> = {
  "btc-usd": {
    feedId: "btc-usd",
    sources: [
      "https://api.coinbase.com/v2/prices/BTC-USD/spot",
      "https://api.kraken.com/0/public/Ticker?pair=XBTUSD",
    ],
    maxAgeSec: 120,
  },
  "eth-usd": {
    feedId: "eth-usd",
    sources: [
      "https://api.coinbase.com/v2/prices/ETH-USD/spot",
      "https://api.kraken.com/0/public/Ticker?pair=ETHUSD",
    ],
    maxAgeSec: 120,
  },
};

export function priceApiHostnames(): string[] {
  const hosts = new Set<string>();
  for (const feed of Object.values(SUPPORTED_FEEDS)) {
    for (const sourceUrl of feed.sources) {
      hosts.add(new URL(sourceUrl).hostname);
    }
  }
  return [...hosts];
}

export interface PriceApiWhitelistNetwork {
  whitelist: (hosts: string | string[]) => void;
}

export function whitelistPriceApiHosts(
  network: PriceApiWhitelistNetwork | undefined,
): void {
  if (!network?.whitelist) {
    return;
  }
  network.whitelist(priceApiHostnames());
}

export interface HttpGetFn {
  (url: string, headers: Record<string, string>): Promise<string>;
}

export interface OracleQuote {
  feedId: string;
  value: string;
  sourcesUsed: number;
  sourceValues: number[];
  fetchedAt: number;
}

/** Collective intelligence: median across independent sources; drop >5% outliers. */
export function aggregateSourcePrices(values: number[]): number {
  if (values.length === 0) {
    throw new Error("no source prices");
  }
  if (values.length === 1) {
    return values[0];
  }

  const median = medianOf(values);
  const filtered = values.filter((value) => {
    const deviation = Math.abs(value - median) / median;
    return deviation <= 0.05;
  });

  const pool = filtered.length > 0 ? filtered : values;
  return medianOf(pool);
}

export function medianOf(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 0) {
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
  return sorted[mid];
}

export function parsePriceFromSource(body: string, sourceUrl: string): number {
  const json = JSON.parse(body) as Record<string, unknown>;

  if (sourceUrl.includes("coinbase.com")) {
    const data = json.data as { amount?: string } | undefined;
    return parseFloat(String(data?.amount ?? ""));
  }
  if (sourceUrl.includes("kraken.com")) {
    const result = json.result as Record<string, { c?: string[] }> | undefined;
    const pair = Object.values(result ?? {})[0];
    return parseFloat(String(pair?.c?.[0] ?? ""));
  }
  throw new Error(`unsupported source parser: ${sourceUrl}`);
}

function assertMinSources(
  feedId: string,
  sourceValues: number[],
  minSources: number,
): void {
  if (sourceValues.length < minSources) {
    throw new Error(
      `insufficient sources for ${feedId}: got ${sourceValues.length}, need ${minSources}`,
    );
  }
}

export async function fetchOracleQuote(
  feedId: string,
  maxAgeSec: number,
  httpGet: HttpGetFn,
  minSources: number,
  nowSec = Math.floor(Date.now() / 1000),
): Promise<OracleQuote> {
  const feed = SUPPORTED_FEEDS[feedId];
  if (!feed) {
    throw new Error(`unsupported feed_id: ${feedId}`);
  }
  if (maxAgeSec > feed.maxAgeSec) {
    throw new Error(`max_age_sec exceeds feed limit (${feed.maxAgeSec})`);
  }

  const sourceValues: number[] = [];
  for (const sourceUrl of feed.sources) {
    try {
      const body = await httpGet(sourceUrl, { Accept: "application/json" });
      const price = parsePriceFromSource(body, sourceUrl);
      if (!Number.isFinite(price) || price <= 0) {
        continue;
      }
      sourceValues.push(price);
    } catch {
      // tolerate single-source failure until minSources is met
    }
  }

  assertMinSources(feedId, sourceValues, minSources);

  const aggregated = aggregateSourcePrices(sourceValues);
  return {
    feedId,
    value: aggregated.toFixed(2),
    sourcesUsed: sourceValues.length,
    sourceValues,
    fetchedAt: nowSec,
  };
}

/** Local dev / unit tests without httpGET. */
export function mockOracleQuote(
  feedId: string,
  sourceValues: number[],
  minSources: number,
  nowSec = Math.floor(Date.now() / 1000),
): OracleQuote {
  assertMinSources(feedId, sourceValues, minSources);
  const aggregated = aggregateSourcePrices(sourceValues);
  return {
    feedId,
    value: aggregated.toFixed(2),
    sourcesUsed: sourceValues.length,
    sourceValues,
    fetchedAt: nowSec,
  };
}
