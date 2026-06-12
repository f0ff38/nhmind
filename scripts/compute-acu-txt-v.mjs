#!/usr/bin/env node
/**
 * Compute Acurast DNS TXT value for _acu.<host> whitelist.
 * Output: v=<base64(sha256(deployment_source || host))>
 *
 * Usage:
 *   node scripts/compute-acu-txt-v.mjs <ss58-or-hex-account> <relay-hostname>
 *   ACURAST_MNEMONIC=... node scripts/compute-acu-txt-v.mjs --from-mnemonic <relay-hostname>
 */
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const require = createRequire(import.meta.url);
const scriptsDir = dirname(fileURLToPath(import.meta.url));

function loadDecodeAddress() {
  try {
    const pkg = join(scriptsDir, "node_modules", "@polkadot/util-crypto");
    const mod = require(join(pkg, "cjs", "address", "index.js"));
    return mod.decodeAddress;
  } catch {
    throw new Error(
      "Run npm ci --prefix scripts (needs @polkadot/util-crypto for SS58 decode)",
    );
  }
}

function sourceBytes(source) {
  if (/^[0-9a-fA-F]{64}$/.test(source)) {
    return Buffer.from(source, "hex");
  }
  const decodeAddress = loadDecodeAddress();
  return Buffer.from(decodeAddress(source));
}

function verificationHash(source, host) {
  const digest = createHash("sha256")
    .update(sourceBytes(source))
    .update(host)
    .digest();
  return `v=${digest.toString("base64")}`;
}

async function addressFromMnemonic(mnemonic) {
  const sdkPath =
    process.env.ACURAST_SDK_CHAIN ??
    "/usr/local/lib/node_modules/@acurast/cli/node_modules/@acurast/sdk/dist/chain/index.js";
  const { pathToFileURL } = await import("node:url");
  const { walletFromMnemonic } = await import(pathToFileURL(sdkPath).href);
  const wallet = await walletFromMnemonic(mnemonic, { name: "AcurastCli" });
  return wallet.address;
}

async function main() {
  const args = process.argv.slice(2);
  let source;
  let host;

  if (args[0] === "--from-mnemonic") {
    host = args[1]?.trim().replace(/\/+$/, "");
    const mnemonic = process.env.ACURAST_MNEMONIC?.trim();
    if (!mnemonic || !host) {
      console.error(
        "usage: ACURAST_MNEMONIC=... node scripts/compute-acu-txt-v.mjs --from-mnemonic <relay-hostname>",
      );
      process.exit(1);
    }
    source = await addressFromMnemonic(mnemonic);
  } else {
    source = args[0]?.trim();
    host = args[1]?.trim().replace(/\/+$/, "");
    if (!source || !host) {
      console.error(
        "usage: node scripts/compute-acu-txt-v.mjs <ss58-or-hex-account> <relay-hostname>",
      );
      process.exit(1);
    }
  }

  host = host.toLowerCase();
  console.log(verificationHash(source, host));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
