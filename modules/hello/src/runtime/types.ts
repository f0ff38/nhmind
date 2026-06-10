export interface AcurastJobId {
  origin: { kind: string; source: string };
  id: string;
}

export interface AcurastPublicKeys {
  p256: string;
  secp256k1: string;
  ed25519: string;
}

export interface AcurastStd {
  app_info: { version: string };
  env: Record<string, string | undefined>;
  job: {
    getId: () => AcurastJobId;
    getSlot: () => number;
    getPublicKeys: () => AcurastPublicKeys;
  };
  device: {
    getPublicKey: () => string;
    getAddress: () => string;
  };
  signers: {
    secp256k1: {
      sign: (payloadHex: string) => string;
      encrypt?: (publicKey: string, salt: string, payloadHex: string) => string;
      decrypt?: (publicKey: string, salt: string, payloadHex: string) => string;
    };
    secp256r1?: {
      sign: (payloadHex: string) => string;
    };
    ed25519?: {
      sign: (payloadHex: string) => string;
    };
  };
  network?: {
    whitelist: (hosts: string | string[]) => void;
  };
  /**
   * Acurast P2P websocket mesh — not a generic client for external Nostr relays.
   * See docs/nostr-protocol.md (Acurast runtime).
   */
  ws?: {
    open: (
      url: string | string[],
      success: () => void,
      error: (message: string) => void,
    ) => void;
    close: (success: () => void, error: (message: string) => void) => void;
    registerPayloadHandler: (handler: (payload: {
      sender: string;
      recipient: string;
      payload: string;
    }) => void) => void;
    send: (
      recipient: string,
      payloadHex: string,
      success: () => void,
      error: (message: string) => void,
    ) => void;
  };
}

declare global {
  // Acurast processors inject this global at runtime.
  // eslint-disable-next-line no-var
  var _STD_: AcurastStd;

  function httpGET(
    url: string,
    headers: Record<string, string>,
    success: (payload: string, certificate: string) => void,
    error: (message: string) => void,
  ): void;

  function httpPOST(
    url: string,
    body: string,
    headers: Record<string, string>,
    success: (payload: string, certificate: string) => void,
    error: (message: string) => void,
  ): void;
}

export function getStd(): AcurastStd {
  return globalThis._STD_;
}

export function isAcurastProcessor(): boolean {
  return getStd().job.getId().origin.kind !== "local";
}
