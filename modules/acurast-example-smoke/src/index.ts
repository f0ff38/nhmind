import os from "node:os";

const { runBenchmark } = require("./bench-core.js") as {
  runBenchmark: (scale: number, tmpDir: string) => Record<string, unknown>;
};

const NO_WEBHOOK_SENTINEL = "__NHMIND_NO_WEBHOOK__";

interface RuntimeStd {
  app_info: { version: string };
  job: {
    getId: () => unknown;
    storageDir: string;
  };
  device: { getAddress: () => string };
  env?: Record<string, string | undefined>;
}

declare const _STD_: RuntimeStd | undefined;

function getStd(): RuntimeStd {
  if (typeof _STD_ !== "undefined") {
    return _STD_;
  }

  return {
    app_info: { version: "local" },
    job: {
      getId: () => "local",
      storageDir: os.tmpdir(),
    },
    device: { getAddress: () => "local" },
    env: process.env,
  };
}

async function networkBench(): Promise<Record<string, unknown>> {
  if (process.env.EXAMPLE_SMOKE_SKIP_NETWORK === "1") {
    return {
      skipped: true,
      throughput_mbps: null,
      download_ms: null,
      parallel_ms: null,
      parallel_count: null,
    };
  }

  const downloadUrl = "https://speed.cloudflare.com/__down?bytes=10000000";
  const smallUrl = "https://speed.cloudflare.com/__down?bytes=100000";
  const parallel = 20;

  try {
    const t0 = Date.now();
    const buf = await (await fetch(downloadUrl)).arrayBuffer();
    const downloadMs = Date.now() - t0;
    const throughputMbps = (buf.byteLength * 8) / 1e6 / (downloadMs / 1000);

    const p0 = Date.now();
    await Promise.all(
      Array.from({ length: parallel }, () =>
        fetch(smallUrl).then((response) => response.arrayBuffer()),
      ),
    );
    const parallelMs = Date.now() - p0;

    return {
      throughput_mbps: Math.round(throughputMbps * 100) / 100,
      download_ms: downloadMs,
      parallel_ms: parallelMs,
      parallel_count: parallel,
    };
  } catch (error) {
    console.log(
      "network benchmark failed:",
      error instanceof Error ? error.message : String(error),
    );
    return {
      throughput_mbps: null,
      download_ms: null,
      parallel_ms: null,
      parallel_count: null,
    };
  }
}

async function postWebhook(webhookUrl: string, payload: unknown): Promise<void> {
  const url = webhookUrl.replace(/\/$/, "");
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  console.log("report POST status:", response.status);
}

async function main(): Promise<void> {
  const std = getStd();
  const scale = Number(process.env.EXAMPLE_SMOKE_SCALE ?? "1");
  const bench = runBenchmark(Number.isFinite(scale) ? scale : 1, std.job.storageDir);
  const network = await networkBench();
  const webhookUrl = process.env.WEBHOOK_URL ?? std.env?.WEBHOOK_URL ?? "";

  const payload = {
    environment: "acurast-example-smoke",
    source: "Acurast/acurast-example-apps app-benchmark-nodejs",
    deploymentId: std.job.getId(),
    deviceAddress: std.device.getAddress(),
    runtimeVersion: std.app_info.version,
    network,
    timestamp: Date.now(),
    ...bench,
  };

  console.log(JSON.stringify(payload, null, 2));

  if (!webhookUrl || webhookUrl === NO_WEBHOOK_SENTINEL) {
    console.log("WEBHOOK_URL not set; skipping report POST");
    return;
  }

  try {
    await postWebhook(webhookUrl, payload);
  } catch (error) {
    console.log(
      "report POST failed:",
      error instanceof Error ? error.message : String(error),
    );
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
