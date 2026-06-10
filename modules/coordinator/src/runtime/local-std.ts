import type { AcurastStd } from "./types";

const LOCAL_SECP256K1_PUB =
  "02fcf1a928bab608989a0218831efd585d1e771669756e1033c60cff4bef6f28e5";

export function createLocalStd(
  env: Record<string, string | undefined> = {},
): AcurastStd {
  return {
    app_info: { version: "local" },
    env: {
      RELAY_URL: env.RELAY_URL ?? "ws://nostr-relay:8080",
      COORDINATOR_WATCH_MODULES: env.COORDINATOR_WATCH_MODULES ?? "hello",
      ACURAST_DEPLOY_ENABLED: env.ACURAST_DEPLOY_ENABLED ?? "false",
      ...env,
    },
    job: {
      getId: () => ({
        origin: { kind: "local", source: "nhmind-dev" },
        id: "coordinator-0",
      }),
      getSlot: () => 0,
      getPublicKeys: () => ({
        p256: "03" + "0".repeat(64),
        secp256k1: LOCAL_SECP256K1_PUB,
        ed25519: "0".repeat(64),
      }),
    },
    device: {
      getPublicKey: () => LOCAL_SECP256K1_PUB,
      getAddress: () => "local-coordinator",
    },
    signers: {
      secp256k1: {
        sign: (payload: string) => `mock-sig:${payload.slice(0, 16)}`,
      },
    },
  };
}

export function installLocalStd(
  env: Record<string, string | undefined> = process.env as Record<
    string,
    string | undefined
  >,
): void {
  if (typeof globalThis._STD_ !== "undefined") {
    return;
  }

  globalThis._STD_ = createLocalStd(env);
  console.log("[nhmind] Installed local _STD_ mock (not running on Acurast TEE)");
}
