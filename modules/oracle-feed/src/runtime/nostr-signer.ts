import {
  createAcurastSigner,
  createEphemeralSigner,
  type Signer,
} from "@nhmind/nostr-client";
import { getStd, isAcurastProcessor } from "./types";

export function createModuleSigner(): Signer {
  const std = getStd();
  if (isAcurastProcessor()) {
    return createAcurastSigner(std);
  }
  return createEphemeralSigner();
}
