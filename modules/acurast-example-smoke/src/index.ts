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

interface RuntimeContext {
  deploymentId: unknown;
  deviceAddress: string;
  runtimeVersion: string;
}

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

function getWebhookUrl(std: RuntimeStd): string {
  return process.env.WEBHOOK_URL ?? std.env?.WEBHOOK_URL ?? "";
}

function getEnvFlag(std: RuntimeStd, name: string): boolean {
  const value = process.env[name] ?? std.env?.[name] ?? "";
  return value === "1" || value.toLowerCase() === "true";
}

function isWebhookEnabled(webhookUrl: string): boolean {
  return Boolean(webhookUrl) && webhookUrl !== NO_WEBHOOK_SENTINEL;
}

function formatError(error: unknown): Record<string, unknown> {
  if (error instanceof Error) {
    return {
      name: error.name,
      message: error.message,
      stack: error.stack,
    };
  }
  return { message: String(error) };
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

function createReporter(webhookUrl: string, context: RuntimeContext) {
  return async (event: string, extra: Record<string, unknown> = {}): Promise<void> => {
    const payload = {
      environment: "acurast-example-smoke",
      source: "Acurast/acurast-example-apps app-benchmark-nodejs",
      event,
      timestamp: Date.now(),
      ...context,
      ...extra,
    };

    console.log(`breadcrumb:${event}`, JSON.stringify(extra));

    if (!isWebhookEnabled(webhookUrl)) {
      return;
    }

    try {
      await postWebhook(webhookUrl, payload);
    } catch (error) {
      console.log("breadcrumb POST failed:", JSON.stringify(formatError(error)));
    }
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

async function main(): Promise<void> {
  console.log("acurast-example-smoke entrypoint");
  const std = getStd();
  const context = {
    deploymentId: std.job.getId(),
    deviceAddress: std.device.getAddress(),
    runtimeVersion: std.app_info.version,
  };
  const webhookUrl = getWebhookUrl(std);
  const report = createReporter(webhookUrl, context);
  try {
    await report("started", {
      nodeVersion: process.version,
      platform: process.platform,
      arch: process.arch,
      webhookEnabled: isWebhookEnabled(webhookUrl),
    });

    await report("std-loaded");

    if (getEnvFlag(std, "EXAMPLE_SMOKE_MINIMAL")) {
      const payload = {
        environment: "acurast-example-smoke",
        source: "nhmind ultra-minimal smoke",
        mode: "minimal",
        ...context,
        timestamp: Date.now(),
        node_version: process.version,
        platform: process.platform,
        arch: process.arch,
      };

      await report("minimal-done", { payloadKeys: Object.keys(payload) });
      console.log(JSON.stringify(payload, null, 2));

      if (!isWebhookEnabled(webhookUrl)) {
        console.log("WEBHOOK_URL not set; skipping minimal report POST");
        await report("done", { mode: "minimal", reportPosted: false });
        return;
      }

      await postWebhook(webhookUrl, payload);
      await report("done", { mode: "minimal", reportPosted: true });
      return;
    }

    const scale = Number(process.env.EXAMPLE_SMOKE_SCALE ?? "1");

    await report("bench-start", { scale: Number.isFinite(scale) ? scale : 1 });
    const bench = runBenchmark(Number.isFinite(scale) ? scale : 1, std.job.storageDir);
    await report("bench-done", { resultKeys: Object.keys(bench) });

    await report("network-start");
    const network = await networkBench();
    await report("network-done", { network });

    const payload = {
      environment: "acurast-example-smoke",
      source: "Acurast/acurast-example-apps app-benchmark-nodejs",
      ...context,
      network,
      timestamp: Date.now(),
      ...bench,
    };

    await report("payload-ready", { payloadKeys: Object.keys(payload) });
    console.log(JSON.stringify(payload, null, 2));

    if (!isWebhookEnabled(webhookUrl)) {
      console.log("WEBHOOK_URL not set; skipping report POST");
      await report("done", { reportPosted: false });
      return;
    }

    try {
      await postWebhook(webhookUrl, payload);
      await report("done", { reportPosted: true });
    } catch (error) {
      console.log(
        "report POST failed:",
        error instanceof Error ? error.message : String(error),
      );
      await report("catch-error", {
        stage: "final-report-post",
        error: formatError(error),
      });
    }
  } catch (error) {
    await report("catch-error", {
      stage: "main",
      error: formatError(error),
    });
    throw error;
  }
}

process.on("unhandledRejection", (reason) => {
  console.log("unhandledRejection:", JSON.stringify(formatError(reason)));
});

process.on("uncaughtException", (error) => {
  console.log("uncaughtException:", JSON.stringify(formatError(error)));
  process.exitCode = 1;
});

main().catch((error: unknown) => {
  console.error(error);
  console.log("main catch:", JSON.stringify(formatError(error)));
  process.exit(1);
});
