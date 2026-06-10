import type { Event, EventTemplate, Filter } from "nostr-tools";
import { getRelayBackend, type RelayBackend } from "./transport";
import type { Signer } from "./signer";

export interface NostrClientOptions {
  relays: string[];
  signer: Signer;
}

export interface SubscribeHandlers {
  onevent: (event: Event) => void;
  oneose?: () => void;
}

export class NostrClient {
  private backend: RelayBackend | undefined;
  private closed = false;

  constructor(private readonly options: NostrClientOptions) {
    if (options.relays.length === 0) {
      throw new Error("at least one relay URL is required");
    }
  }

  get relays(): readonly string[] {
    return this.options.relays;
  }

  get publicKey(): string {
    return this.options.signer.getPublicKey();
  }

  sign(template: EventTemplate): Event {
    return this.options.signer.signEvent(template);
  }

  async get(filter: Filter, maxWaitMs = 5_000): Promise<Event | null> {
    this.ensureOpen();
    return this.resolveBackend().get(this.options.relays, filter, maxWaitMs);
  }

  async publish(template: EventTemplate): Promise<Event> {
    this.ensureOpen();
    const event = this.sign(template);
    await this.resolveBackend().publish(this.options.relays, event);
    return event;
  }

  subscribe(filters: Filter[], handlers: SubscribeHandlers): () => void {
    this.ensureOpen();
    return this.resolveBackend().subscribe(this.options.relays, filters, handlers);
  }

  async close(): Promise<void> {
    if (this.closed) {
      return;
    }
    this.closed = true;
    if (this.backend) {
      await this.backend.close(this.options.relays);
    }
  }

  private resolveBackend(): RelayBackend {
    if (!this.backend) {
      this.backend = getRelayBackend();
    }
    return this.backend;
  }

  private ensureOpen(): void {
    if (this.closed) {
      throw new Error("NostrClient is closed");
    }
  }
}
