import type { Event, Filter } from "nostr-tools";
import type { RelayBackend } from "./types";

type HttpSuccess = (payload: string, certificate: string) => void;
type HttpError = (message: string) => void;

declare global {
  function httpGET(
    url: string,
    headers: Record<string, string>,
    success: HttpSuccess,
    error: HttpError,
  ): void;
  function httpPOST(
    url: string,
    body: string,
    headers: Record<string, string>,
    success: HttpSuccess,
    error: HttpError,
  ): void;
}

function relayHttpUrl(relayUrl: string): string {
  if (relayUrl.toLowerCase().startsWith("wss://")) {
    return `https://${relayUrl.slice(6)}`;
  }
  if (relayUrl.toLowerCase().startsWith("ws://")) {
    return `http://${relayUrl.slice(5)}`;
  }
  return relayUrl;
}

function httpRequest(
  method: "GET" | "POST",
  url: string,
  body?: string,
): Promise<string> {
  return new Promise((resolve, reject) => {
    const headers: Record<string, string> = {
      Accept: "application/json",
    };
    if (body !== undefined) {
      headers["Content-Type"] = "application/json";
    }

    const onSuccess: HttpSuccess = (payload) => resolve(payload);
    const onError: HttpError = (message) => reject(new Error(message));

    if (method === "GET") {
      httpGET(url, headers, onSuccess, onError);
      return;
    }
    httpPOST(url, body ?? "", headers, onSuccess, onError);
  });
}

function parseEvents(payload: string): Event[] {
  const events: Event[] = [];
  for (const line of payload.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }
    try {
      const message = JSON.parse(trimmed) as unknown;
      if (Array.isArray(message) && message[0] === "EVENT" && message[2]) {
        events.push(message[2] as Event);
      }
    } catch {
      // Ignore non-JSON lines from relays that stream mixed payloads.
    }
  }
  return events;
}

function eventMatchesFilter(event: Event, filter: Filter): boolean {
  if (filter.kinds && !filter.kinds.includes(event.kind)) {
    return false;
  }
  if (filter.authors && !filter.authors.includes(event.pubkey)) {
    return false;
  }
  for (const [tagName, values] of Object.entries(filter)) {
    if (!tagName.startsWith("#") || !values) {
      continue;
    }
    const tagKey = tagName.slice(1);
    const expected = Array.isArray(values)
      ? values.map(String)
      : [String(values)];
    const hasTag = event.tags.some(
      ([key, value]) => key === tagKey && expected.includes(value),
    );
    if (!hasTag) {
      return false;
    }
  }
  return true;
}

export function createAcurastHttpBackend(): RelayBackend {
  if (typeof globalThis.httpPOST !== "function") {
    throw new Error("Acurast httpPOST is not available in this runtime");
  }

  return {
    async publish(relays, event) {
      const body = JSON.stringify(["EVENT", event]);
      const headers = { "Content-Type": "application/json" };
      await Promise.all(
        relays.map((relay) =>
          new Promise<void>((resolve, reject) => {
            httpPOST(
              relayHttpUrl(relay),
              body,
              headers,
              () => resolve(),
              (message) => reject(new Error(message)),
            );
          }),
        ),
      );
    },
    async get(relays, filter, maxWaitMs) {
      const subId = `nhmind-${Date.now()}`;
      const body = JSON.stringify(["REQ", subId, filter]);
      const headers = { "Content-Type": "application/json" };
      const started = Date.now();

      while (Date.now() - started < maxWaitMs) {
        for (const relay of relays) {
          const payload = await new Promise<string>((resolve, reject) => {
            httpPOST(
              relayHttpUrl(relay),
              body,
              headers,
              (response) => resolve(response),
              (message) => reject(new Error(message)),
            );
          });

          const events = parseEvents(payload).filter((event) =>
            eventMatchesFilter(event, filter),
          );
          if (events.length > 0) {
            return events.sort((a, b) => b.created_at - a.created_at)[0] ?? null;
          }
        }
        await new Promise((resolve) => setTimeout(resolve, 250));
      }

      return null;
    },
    subscribe(relays, filters, handlers) {
      let active = true;
      const poll = async (): Promise<void> => {
        while (active) {
          for (const filter of filters) {
            for (const relay of relays) {
              try {
                const subId = `nhmind-sub-${Date.now()}`;
                const body = JSON.stringify(["REQ", subId, filter]);
                const payload = await httpRequest("POST", relayHttpUrl(relay), body);
                for (const event of parseEvents(payload)) {
                  if (eventMatchesFilter(event, filter)) {
                    handlers.onevent(event);
                  }
                }
              } catch {
                // Relay polling is best-effort on Acurast HTTP transport.
              }
            }
          }
          await new Promise((resolve) => setTimeout(resolve, 500));
        }
      };
      void poll();
      return () => {
        active = false;
      };
    },
    async close() {
      // Stateless HTTP transport.
    },
  };
}
