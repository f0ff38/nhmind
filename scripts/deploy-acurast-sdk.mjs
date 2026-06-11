#!/usr/bin/env node
/**
 * Programmatic canary deploy via @acurast/sdk (same stack as `acurast deploy`).
 * Runs outside TEE — for CI/GHA or ops automation, not inside coordinator bundle.
 *
 * Usage:
 *   ACURAST_CANARY_RPC=wss://public-rpc.canary.acurast.com \
 *     node scripts/deploy-acurast-sdk.mjs modules/hello
 *
 * Requires modules/<name>/.env with ACURAST_MNEMONIC (see acurast init).
 */
import { readFileSync, existsSync } from "fs";
import { resolve } from "path";
import { pathToFileURL } from "url";

const sdkDeployPath =
  process.env.ACURAST_SDK_DEPLOY ??
  "/usr/local/lib/node_modules/@acurast/cli/node_modules/@acurast/sdk/dist/deploy/index.js";

const moduleDir = resolve(process.argv[2] ?? "");
if (!moduleDir || !existsSync(resolve(moduleDir, "acurast.json"))) {
  console.error("Usage: node scripts/deploy-acurast-sdk.mjs modules/<name>");
  process.exit(1);
}

const envPath = resolve(moduleDir, ".env");
if (!existsSync(envPath)) {
  console.error(`Missing ${envPath} — run acurast init in the module first.`);
  process.exit(1);
}

for (const line of readFileSync(envPath, "utf8").split("\n")) {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith("#")) {
    continue;
  }
  const eq = trimmed.indexOf("=");
  if (eq === -1) {
    continue;
  }
  const key = trimmed.slice(0, eq);
  let value = trimmed.slice(eq + 1).trim();
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    value = value.slice(1, -1);
  }
  process.env[key] = value;
}

if (!process.env.ACURAST_MNEMONIC) {
  console.error("ACURAST_MNEMONIC not set in module .env");
  process.exit(1);
}

process.env.ACURAST_CANARY_RPC ??=
  "wss://public-rpc.canary.acurast.com";

const bundlePath = resolve(moduleDir, "dist/bundle.js");
if (!existsSync(bundlePath)) {
  console.error(`Missing ${bundlePath} — run npm run bundle in ${moduleDir} first.`);
  process.exit(1);
}

const { loadAcurastConfig, deployProject } = await import(
  pathToFileURL(sdkDeployPath).href
);

const configPath = resolve(moduleDir, "acurast.json");
const config = await loadAcurastConfig(configPath);

console.log(`Deploying via @acurast/sdk: ${moduleDir}`);
await deployProject({
  config,
  cwd: moduleDir,
  nonInteractive: true,
});
