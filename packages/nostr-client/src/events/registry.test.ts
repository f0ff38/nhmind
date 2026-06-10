import { describe, expect, it } from "vitest";
import { generateSecretKey } from "nostr-tools";
import { NHMIND_CLIENT_TAG, KIND_REGISTRY } from "../constants";
import { createPrivateKeySigner } from "../signer";
import {
  buildRegistryTemplate,
  parseRegistryEvent,
  registryDTag,
} from "./registry";

describe("registry events", () => {
  const deploymentId = {
    origin: { kind: "acurast", source: "canary" },
    id: "42",
  };
  const modulePubkey =
    "02fcf1a928bab608989a0218831efd585d1e771669756e1033c60cff4bef6f28e5";

  it("builds a NIP-33 registry template", () => {
    const template = buildRegistryTemplate({
      moduleId: "hello",
      deploymentId,
      modulePubkey,
      network: "canary",
      registeredAt: 1717400000,
      status: "paused",
      createdAt: 1718006400,
    });

    expect(template.kind).toBe(KIND_REGISTRY);
    expect(template.tags).toEqual([
      ["client", NHMIND_CLIENT_TAG],
      ["d", "registry:hello"],
      ["module", "hello"],
      ["deployment", JSON.stringify(deploymentId)],
    ]);

    const content = JSON.parse(template.content);
    expect(content.schema).toBe("nhmind/registry/v1");
    expect(content.status).toBe("paused");
    expect(content.module_pubkey).toBe(modulePubkey);
  });

  it("round-trips through sign and parse", () => {
    const signer = createPrivateKeySigner(generateSecretKey());
    const template = buildRegistryTemplate({
      moduleId: "hello",
      deploymentId,
      modulePubkey,
      network: "canary",
      registeredAt: 1717400000,
      status: "active",
      createdAt: 1718006400,
    });
    const signed = signer.signEvent(template);
    const payload = parseRegistryEvent(signed);

    expect(payload.module_id).toBe("hello");
    expect(payload.status).toBe("active");
    expect(registryDTag("hello")).toBe("registry:hello");
  });
});
