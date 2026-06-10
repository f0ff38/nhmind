import { beforeEach, describe, expect, it } from "vitest";
import { buildCoordinatorConfig, healthCheck, main } from "./app";
import { createLocalStd } from "./runtime/local-std";

describe("coordinator module", () => {
  beforeEach(() => {
    globalThis._STD_ = createLocalStd({
      RELAY_URL: "ws://nostr-relay:8080",
      COORDINATOR_WATCH_MODULES: "hello",
    });
  });

  it("passes health check with relay configured", () => {
    expect(healthCheck()).toEqual({
      ok: true,
      details: "relay=ws://nostr-relay:8080, watch=hello",
    });
  });

  it("fails health check without relay", () => {
    globalThis._STD_ = createLocalStd({ RELAY_URL: "" });
    expect(healthCheck().ok).toBe(false);
  });

  it("parses watch modules from env", () => {
    globalThis._STD_ = createLocalStd({
      RELAY_URL: "ws://nostr-relay:8080",
      COORDINATOR_WATCH_MODULES: "hello,oracle",
    });
    expect(buildCoordinatorConfig().watchModules).toEqual(["hello", "oracle"]);
  });

  it("runs main without throwing when relay is unreachable", async () => {
    const logs: string[] = [];
    const originalLog = console.log;
    const originalWarn = console.warn;
    console.log = (...args: unknown[]) => {
      logs.push(args.map(String).join(" "));
    };
    console.warn = (...args: unknown[]) => {
      logs.push(args.map(String).join(" "));
    };

    try {
      await main();
      expect(logs.some((line) => line.includes("NostrHiveMind coordinator"))).toBe(
        true,
      );
    } finally {
      console.log = originalLog;
      console.warn = originalWarn;
    }
  });
});
