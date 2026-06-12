import { defineConfig } from "vitest/config";

const smokeCoordinator =
  process.env.SMOKE_COORDINATOR_RELAY === "1";

export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.integration.test.ts"],
    testTimeout: smokeCoordinator ? 180_000 : 30_000,
  },
});
