import { describe, expect, it } from "vitest";
import {
  aggregateSourcePrices,
  medianOf,
  mockOracleQuote,
  parsePriceFromSource,
} from "./feeds";

describe("oracle feeds — collective median", () => {
  it("returns median of sources", () => {
    expect(medianOf([1, 3, 9])).toBe(3);
    expect(medianOf([1, 2, 3, 4])).toBe(2.5);
  });

  it("drops >5% outliers before median", () => {
    const value = aggregateSourcePrices([67000, 67010, 66995, 90000]);
    expect(value).toBeCloseTo(67000, 0);
  });

  it("parses coinbase spot payload", () => {
    const price = parsePriceFromSource(
      JSON.stringify({ data: { amount: "67234.12" } }),
      "https://api.coinbase.com/v2/prices/BTC-USD/spot",
    );
    expect(price).toBeCloseTo(67234.12, 2);
  });

  it("builds mock quote for local dev", () => {
    const quote = mockOracleQuote("btc-usd", [67000.12, 67010.5, 66995.0]);
    expect(quote.feedId).toBe("btc-usd");
    expect(Number(quote.value)).toBeGreaterThan(66990);
    expect(quote.sourcesUsed).toBe(3);
  });
});
