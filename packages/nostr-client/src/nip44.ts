import { nip44 } from "nostr-tools";

export function getConversationKey(
  privateKey: Uint8Array,
  publicKey: string,
): Uint8Array {
  return nip44.v2.utils.getConversationKey(privateKey, publicKey);
}

export function encryptPayload(
  senderPrivateKey: Uint8Array,
  recipientPublicKey: string,
  plaintext: string,
): string {
  const conversationKey = getConversationKey(
    senderPrivateKey,
    recipientPublicKey,
  );
  return nip44.v2.encrypt(plaintext, conversationKey);
}

export function decryptPayload(
  recipientPrivateKey: Uint8Array,
  senderPublicKey: string,
  ciphertext: string,
): string {
  const conversationKey = getConversationKey(
    recipientPrivateKey,
    senderPublicKey,
  );
  return nip44.v2.decrypt(ciphertext, conversationKey);
}
