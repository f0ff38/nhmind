import type { Event, Filter } from "nostr-tools";

export interface RelayBackend {
  publish(relays: string[], event: Event): Promise<void>;
  get(relays: string[], filter: Filter, maxWaitMs: number): Promise<Event | null>;
  subscribe(
    relays: string[],
    filters: Filter[],
    handlers: { onevent: (event: Event) => void; oneose?: () => void },
  ): () => void;
  close(relays: string[]): Promise<void>;
}
