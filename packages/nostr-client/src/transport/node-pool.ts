import type { Event, Filter } from "nostr-tools";
import type { RelayBackend } from "./types";

type SimplePoolInstance = {
  publish: (relays: string[], event: Event) => Promise<string>[];
  get: (
    relays: string[],
    filter: Filter,
    params?: { maxWait?: number },
  ) => Promise<Event | null>;
  subscribeMany: (
    relays: string[],
    filter: Filter,
    handlers: { onevent: (event: Event) => void; oneose?: () => void },
  ) => { close: () => void };
  close: (relays: string[]) => void;
};

type PoolModule = {
  SimplePool: new () => SimplePoolInstance;
  useWebSocketImplementation: (impl: new () => WebSocket) => void;
};

// Static require so webpack bundles pool into hello dist/bundle.js.
// eslint-disable-next-line @typescript-eslint/no-require-imports
const poolModule = require("nostr-tools/pool") as PoolModule;

function loadNodeWebSocket(): (new () => WebSocket) | undefined {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const wsModule = require("ws") as { default?: new () => WebSocket };
    return (wsModule.default ?? wsModule) as new () => WebSocket;
  } catch {
    return undefined;
  }
}

export function createNodePoolBackend(): RelayBackend {
  const WebSocketImpl = loadNodeWebSocket();
  if (!WebSocketImpl) {
    throw new Error(
      "Node WebSocket (ws) is not available; install optional dependency or use Acurast httpPOST runtime",
    );
  }

  poolModule.useWebSocketImplementation(WebSocketImpl);
  const pool = new poolModule.SimplePool();

  return {
    async publish(relays, event) {
      await Promise.all(pool.publish(relays, event));
    },
    async get(relays, filter, maxWaitMs) {
      return pool.get(relays, filter, { maxWait: maxWaitMs });
    },
    subscribe(relays, filters, handlers) {
      const closers = filters.map((filter) =>
        pool.subscribeMany(relays, filter, handlers),
      );
      return () => {
        for (const closer of closers) {
          closer.close();
        }
      };
    },
    async close(relays) {
      pool.close(relays);
    },
  };
}
