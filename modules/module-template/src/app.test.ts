import { beforeEach, describe, expect, it } from "vitest";
import { healthCheck, main } from "./app";
import { createLocalStd } from "./runtime/local-std";

describe("template module", () => {
  beforeEach(() => {
    globalThis._STD_ = createLocalStd({ RELAY_URL: "ws://nostr-relay:8080" });
  });

  it("passes health check with relay configured", () => {
    expect(healthCheck()).toEqual({
      ok: true,
      details: "relay=ws://nostr-relay:8080, version=local",
    });
  });

  it("fails health check without relay", () => {
    globalThis._STD_ = createLocalStd({ RELAY_URL: "" });
    expect(healthCheck().ok).toBe(false);
  });

  it("runs main without throwing", async () => {
    const logs: string[] = [];
    const originalLog = console.log;
    console.log = (...args: unknown[]) => {
      logs.push(args.map(String).join(" "));
    };

    try {
      await main();
      expect(
        logs.some((line) => line.includes("NostrHiveMind template module")),
      ).toBe(true);
    } finally {
      console.log = originalLog;
    }
  });
});
