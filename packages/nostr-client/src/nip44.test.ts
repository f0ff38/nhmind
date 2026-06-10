import { describe, expect, it } from "vitest";
import { generateSecretKey, getPublicKey } from "nostr-tools";
import { decryptPayload, encryptPayload } from "./nip44";

describe("NIP-44", () => {
  it("round-trips plaintext between two keys", () => {
    const alice = generateSecretKey();
    const bob = generateSecretKey();
    const alicePub = getPublicKey(alice);
    const bobPub = getPublicKey(bob);

    const ciphertext = encryptPayload(alice, bobPub, '{"secret":"value"}');
    const plaintext = decryptPayload(bob, alicePub, ciphertext);

    expect(JSON.parse(plaintext)).toEqual({ secret: "value" });
  });

  it("fails decryption with the wrong recipient key", () => {
    const alice = generateSecretKey();
    const bob = generateSecretKey();
    const eve = generateSecretKey();

    const ciphertext = encryptPayload(alice, getPublicKey(bob), "hello");

    expect(() => decryptPayload(eve, getPublicKey(alice), ciphertext)).toThrow();
  });
});
