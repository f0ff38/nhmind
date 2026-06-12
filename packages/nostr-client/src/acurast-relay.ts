/**
 * Relay hostname extraction and Acurast processor network whitelist.
 * @see docs/nostr-protocol.md (Acurast runtime)
 */

export function relayHostnameFromUrl(relayUrl: string): string {
  const trimmed = relayUrl.trim();
  const withScheme = /^wss?:\/\//i.test(trimmed)
    ? trimmed
    : `https://${trimmed}`;
  const normalized = withScheme
    .replace(/^wss:\/\//i, "https://")
    .replace(/^ws:\/\//i, "http://");
  return new URL(normalized).hostname;
}

export interface RelayWhitelistNetwork {
  whitelist: (hosts: string | string[]) => void;
}

export function whitelistRelayHost(
  network: RelayWhitelistNetwork | undefined,
  relayUrl: string,
): void {
  if (!network?.whitelist) {
    return;
  }
  network.whitelist(relayHostnameFromUrl(relayUrl));
}
