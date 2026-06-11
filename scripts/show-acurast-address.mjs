#!/usr/bin/env node
/**
 * Print deploy wallet address from module .env (same derivation as acurast deploy).
 * Usage: node scripts/show-acurast-address.mjs modules/hello
 */
import { readFileSync } from "fs";
import { resolve } from "path";
import { pathToFileURL } from "url";

const sdkPath =
  process.env.ACURAST_SDK_CHAIN ??
  "/usr/local/lib/node_modules/@acurast/cli/node_modules/@acurast/sdk/dist/chain/index.js";
const { walletFromMnemonic } = await import(pathToFileURL(sdkPath).href);

const moduleDir = resolve(process.argv[2] ?? "modules/hello");
const envPath = resolve(moduleDir, ".env");
const env = readFileSync(envPath, "utf8");
const match = env.match(/^ACURAST_MNEMONIC=(.+)$/m);

if (!match) {
  console.error(`ACURAST_MNEMONIC not found in ${envPath}`);
  process.exit(1);
}

const mnemonic = match[1].trim().replace(/^["']|["']$/g, "");
const wallet = await walletFromMnemonic(mnemonic, { name: "AcurastCli" });
console.log(wallet.address);
