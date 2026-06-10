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
      sign: (payload: string) => string;
    };
  };
}

declare global {
  // Acurast processors inject this global at runtime.
  // eslint-disable-next-line no-var
  var _STD_: AcurastStd;
}

export function getStd(): AcurastStd {
  return globalThis._STD_;
}
