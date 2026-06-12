import { describe, expect, it } from "vitest";
import { relayHostnameFromUrl } from "./acurast-relay";

describe("relayHostnameFromUrl", () => {
  it("extracts host from wss URL", () => {
    expect(relayHostnameFromUrl("wss://nostr.example.com/")).toBe(
      "nostr.example.com",
    );
  });

  it("extracts host from ws URL with path", () => {
    expect(relayHostnameFromUrl("ws://relay.local:8080/nostr")).toBe(
      "relay.local",
    );
  });
});
