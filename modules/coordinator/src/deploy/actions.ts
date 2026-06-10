import type { DeploymentId, Verdict } from "@nhmind/nostr-client";

export interface DeployActions {
  applyVerdict(
    moduleId: string,
    verdict: Verdict,
    deploymentId: DeploymentId,
  ): Promise<void>;
}

export function createStubDeployActions(): DeployActions {
  return {
    async applyVerdict(moduleId, verdict, deploymentId) {
      console.log(
        `[coordinator] deploy stub: ${moduleId} → ${verdict}`,
        JSON.stringify(deploymentId),
      );
    },
  };
}

export function createDeployActions(
  env: Record<string, string | undefined>,
): DeployActions {
  if (env.ACURAST_DEPLOY_ENABLED?.trim().toLowerCase() === "true") {
    console.warn(
      "[coordinator] ACURAST_DEPLOY_ENABLED=true but SDK deploy is not bundled in TEE; using stub",
    );
  }
  return createStubDeployActions();
}
