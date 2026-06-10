import {
  finalizeEvent,
  generateSecretKey,
  getEventHash,
  getPublicKey,
  type Event,
  type EventTemplate,
  type UnsignedEvent,
} from "nostr-tools";

export interface Signer {
  getPublicKey(): string;
  signEvent(template: EventTemplate): Event;
}

export interface AcurastSigningStd {
  job: {
    getPublicKeys: () => { secp256k1: string };
  };
  signers: {
    secp256k1: {
      sign: (payloadHex: string) => string;
    };
  };
}

export function createPrivateKeySigner(secretKey: Uint8Array): Signer {
  const pubkey = getPublicKey(secretKey);
  return {
    getPublicKey: () => pubkey,
    signEvent: (template) => finalizeEvent(template, secretKey),
  };
}

let cachedEphemeralSecretKey: Uint8Array | undefined;

export function createEphemeralSigner(): Signer {
  if (!cachedEphemeralSecretKey) {
    cachedEphemeralSecretKey = generateSecretKey();
  }
  return createPrivateKeySigner(cachedEphemeralSecretKey);
}

export function createAcurastSigner(std: AcurastSigningStd): Signer {
  const pubkey = std.job.getPublicKeys().secp256k1;
  return {
    getPublicKey: () => pubkey,
    signEvent: (template) => {
      const unsigned: UnsignedEvent = {
        ...template,
        pubkey,
      };
      const id = getEventHash(unsigned);
      const sig = std.signers.secp256k1.sign(id);
      return { ...unsigned, id, sig };
    },
  };
}
