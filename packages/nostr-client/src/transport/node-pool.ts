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

function loadNodeWebSocket(): new () => WebSocket {
  // Dynamic require keeps `ws` out of Acurast webpack bundles.
  const dynamicRequire = (moduleName: string): unknown => {
    // eslint-disable-next-line no-eval
    return eval("require")(moduleName);
  };

  const wsModule = dynamicRequire("ws") as { default?: new () => WebSocket };
  const WebSocketImpl = wsModule.default ?? wsModule;
  return WebSocketImpl as new () => WebSocket;
}

function loadSimplePool(): new () => SimplePoolInstance {
  const dynamicRequire = (moduleName: string): unknown => {
    // eslint-disable-next-line no-eval
    return eval("require")(moduleName);
  };

  const poolModule = dynamicRequire("nostr-tools/pool") as {
    SimplePool: new () => SimplePoolInstance;
    useWebSocketImplementation: (impl: new () => WebSocket) => void;
  };

  poolModule.useWebSocketImplementation(loadNodeWebSocket());
  return poolModule.SimplePool;
}

export function createNodePoolBackend(): RelayBackend {
  const SimplePool = loadSimplePool();
  const pool = new SimplePool();

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
