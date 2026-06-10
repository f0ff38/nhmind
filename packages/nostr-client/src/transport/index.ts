import type { RelayBackend } from "./types";
import { createAcurastHttpBackend } from "./acurast-http";
import { createNodePoolBackend } from "./node-pool";

let backend: RelayBackend | undefined;

export function isAcurastHttpRuntime(): boolean {
  return typeof globalThis.httpPOST === "function";
}

export function configureRelayBackend(next: RelayBackend): void {
  backend = next;
}

export function getRelayBackend(): RelayBackend {
  if (backend) {
    return backend;
  }

  if (isAcurastHttpRuntime()) {
    backend = createAcurastHttpBackend();
    return backend;
  }

  backend = createNodePoolBackend();
  return backend;
}

export function resetRelayBackend(): void {
  backend = undefined;
}

export type { RelayBackend } from "./types";
