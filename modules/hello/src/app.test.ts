import { beforeEach, describe, expect, it } from "vitest";
import { healthCheck, main, publishHeartbeat } from "./app";
import { createLocalStd } from "./runtime/local-std";

describe("hello module", () => {
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

  it("skips heartbeat publish when relay url is missing", async () => {
    globalThis._STD_ = createLocalStd({ RELAY_URL: "" });
    expect(await publishHeartbeat()).toBe(false);
  });

  it("skips relay whitelist when RELAY_SKIP_WHITELIST is set", async () => {
    const whitelisted: string[] = [];
    globalThis._STD_ = {
      ...createLocalStd({ RELAY_URL: "ws://nostr-relay:8080", RELAY_SKIP_WHITELIST: "1" }),
      network: {
        whitelist: (hosts) => {
          whitelisted.push(String(hosts));
        },
      },
    };
    await publishHeartbeat();
    expect(whitelisted).toEqual([]);
  });

  it("runs main without throwing", async () => {
    const logs: string[] = [];
    const originalLog = console.log;
    console.log = (...args: unknown[]) => {
      logs.push(args.map(String).join(" "));
    };

    try {
      await main();
      expect(logs.some((line) => line.includes("NostrHiveMind hello module"))).toBe(
        true,
      );
    } finally {
      console.log = originalLog;
    }
  });
});
