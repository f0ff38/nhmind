import { defineConfig } from "vitest/config";

const smokeCoordinator =
  process.env.SMOKE_COORDINATOR_RELAY === "1";
const smokeTimeoutMs = Number(process.env.SMOKE_TIMEOUT_MS ?? "120000");

export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.integration.test.ts"],
    // Vitest cap must cover waitForEvent (SMOKE_TIMEOUT_MS) plus client overhead.
    testTimeout: smokeCoordinator ? smokeTimeoutMs + 10_000 : 30_000,
  },
});
