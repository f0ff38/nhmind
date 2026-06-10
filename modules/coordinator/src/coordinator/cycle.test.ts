import { describe, expect, it, vi } from "vitest";
import { generateSecretKey } from "nostr-tools";
import {
  buildHeartbeatTemplate,
  createPrivateKeySigner,
  type NostrClient,
} from "@nhmind/nostr-client";
import { createStubDeployActions } from "../deploy/actions";
import { runCoordinatorCycle } from "./cycle";

describe("runCoordinatorCycle", () => {
  const deploymentId = {
    origin: { kind: "local", source: "nhmind-dev" },
    id: "0",
  };

  it("registers module from heartbeat and publishes registry + scorecard", async () => {
    const moduleSigner = createPrivateKeySigner(generateSecretKey());
    const heartbeatTemplate = buildHeartbeatTemplate({
      moduleId: "hello",
      deploymentId,
      health: { ok: true, details: "ok" },
      appVersion: "0.1.0",
      createdAt: 1718000000,
    });
    const heartbeatEvent = moduleSigner.signEvent(heartbeatTemplate);

    const publish = vi.fn(async (template: Parameters<NostrClient["publish"]>[0]) => ({
      ...moduleSigner.signEvent(template),
      id: `evt-${template.kind}`,
    }));

    const client = {
      get: vi.fn(async () => heartbeatEvent),
      publish,
      close: vi.fn(),
    } as unknown as NostrClient;

    const deploy = createStubDeployActions();
    const applyVerdict = vi.spyOn(deploy, "applyVerdict");

    const result = await runCoordinatorCycle({
      client,
      deploy,
      config: {
        relayUrl: "ws://nostr-relay:8080",
        watchModules: ["hello"],
        network: "local",
        coordinatorDeploymentId: deploymentId,
      },
      now: () => 1718006400,
    });

    expect(result.modules).toHaveLength(1);
    expect(result.modules[0]).toMatchObject({
      moduleId: "hello",
      registered: true,
      verdict: "pause",
      registryPublished: true,
      scorecardPublished: true,
    });
    expect(applyVerdict).toHaveBeenCalledWith("hello", "pause", deploymentId);
    expect(publish).toHaveBeenCalledTimes(2);
  });

  it("skips modules without heartbeat", async () => {
    const client = {
      get: vi.fn(async () => null),
      publish: vi.fn(),
      close: vi.fn(),
    } as unknown as NostrClient;

    const result = await runCoordinatorCycle({
      client,
      deploy: createStubDeployActions(),
      config: {
        relayUrl: "ws://nostr-relay:8080",
        watchModules: ["missing"],
        network: "local",
        coordinatorDeploymentId: deploymentId,
      },
    });

    expect(result.modules[0]).toMatchObject({
      moduleId: "missing",
      registered: false,
      verdict: "none",
    });
  });
});
