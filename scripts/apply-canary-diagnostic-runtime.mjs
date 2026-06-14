#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";

const configPath = process.argv[2];
if (!configPath) {
  console.error("usage: apply-canary-diagnostic-runtime.mjs <acurast.json>");
  process.exit(1);
}

const config = JSON.parse(readFileSync(configPath, "utf8"));
const [projectName, project] = Object.entries(config.projects ?? {})[0] ?? [];

if (!projectName || !project) {
  console.error(`No project found in ${configPath}`);
  process.exit(1);
}

if (projectName !== "hello") {
  console.error(`Diagnostic runtime is only supported for hello, got ${projectName}`);
  process.exit(1);
}

project.execution = {
  ...project.execution,
  type: "onetime",
  maxExecutionTimeInMs: 300000,
};
project.maxAllowedStartDelayInMs = 300000;
project.maxCostPerExecution = 50000000000;

writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);

console.log("Applied hello diagnostic runtime overrides:");
console.log("- execution.maxExecutionTimeInMs=300000");
console.log("- maxAllowedStartDelayInMs=300000");
console.log("- maxCostPerExecution=50000000000");
