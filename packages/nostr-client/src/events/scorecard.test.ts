import { describe, expect, it } from "vitest";
import { generateSecretKey } from "nostr-tools";
import { NHMIND_CLIENT_TAG, KIND_SCORECARD } from "../constants";
import { createPrivateKeySigner } from "../signer";
import {
  buildScorecardTemplate,
  parseScorecardEvent,
  scorecardDTag,
} from "./scorecard";

describe("scorecard events", () => {
  const deploymentId = {
    origin: { kind: "acurast", source: "canary" },
    id: "42",
  };

  it("builds a NIP-33 scorecard template", () => {
    const template = buildScorecardTemplate({
      moduleId: "hello",
      deploymentId,
      windowStart: 1717400000,
      windowEnd: 1718006400,
      revenueAcu: "1000000",
      costAcu: "800000",
      relayFeesAcu: "0",
      roi: 1.25,
      verdict: "promote",
      verdictReason: "ROI >= 1.0",
      createdAt: 1718006400,
    });

    expect(template.kind).toBe(KIND_SCORECARD);
    expect(template.tags).toEqual([
      ["client", NHMIND_CLIENT_TAG],
      ["d", "scorecard:hello"],
      ["module", "hello"],
      ["deployment", JSON.stringify(deploymentId)],
    ]);

    const content = JSON.parse(template.content);
    expect(content.schema).toBe("nhmind/scorecard/v1");
    expect(content.verdict).toBe("promote");
    expect(content.roi).toBe(1.25);
  });

  it("round-trips through sign and parse", () => {
    const signer = createPrivateKeySigner(generateSecretKey());
    const template = buildScorecardTemplate({
      moduleId: "hello",
      deploymentId,
      windowStart: 1717400000,
      windowEnd: 1718006400,
      revenueAcu: "0",
      costAcu: "0",
      relayFeesAcu: "0",
      roi: 0,
      verdict: "pause",
      verdictReason: "stub metrics",
      createdAt: 1718006400,
    });
    const signed = signer.signEvent(template);
    const payload = parseScorecardEvent(signed);

    expect(payload.module_id).toBe("hello");
    expect(payload.verdict).toBe("pause");
    expect(scorecardDTag("hello")).toBe("scorecard:hello");
  });
});
