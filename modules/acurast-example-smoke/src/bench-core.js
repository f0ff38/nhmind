// Adapted from Acurast/acurast-example-apps:
// apps/benchmarks/app-benchmark-nodejs/app/bench-core.js
//
// Pure JS workload used by the official native Node.js benchmark example.
// It intentionally exercises CPU, crypto, JSON, file I/O, and memory.

const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");

function time(fn) {
  const start = process.hrtime.bigint();
  fn();
  const end = process.hrtime.bigint();
  return Number(end - start) / 1e6;
}

function primesBench(n) {
  let count = 0;
  for (let i = 2; i < n; i++) {
    let isPrime = true;
    for (let j = 2; j * j <= i; j++) {
      if (i % j === 0) {
        isPrime = false;
        break;
      }
    }
    if (isPrime) count++;
  }
  return count;
}

function hashBench(iterations) {
  let buf = Buffer.alloc(1024, 7);
  for (let i = 0; i < iterations; i++) {
    buf = crypto.createHash("sha256").update(buf).digest();
  }
  return buf.toString("hex");
}

function jsonBench(iterations) {
  const obj = {
    a: 1,
    b: "hello world",
    c: [1, 2, 3, 4, 5],
    d: { nested: true, arr: new Array(50).fill(0).map((_, i) => i) },
  };
  let acc = 0;
  for (let i = 0; i < iterations; i++) {
    const s = JSON.stringify(obj);
    const o = JSON.parse(s);
    acc += s.length + o.c.length;
  }
  return acc;
}

function fileIoBench(numFiles, baseDir) {
  const dir = fs.mkdtempSync(path.join(baseDir, "bench-"));
  const data = Buffer.alloc(4096, 42);
  for (let i = 0; i < numFiles; i++) {
    const f = path.join(dir, `f${i}`);
    fs.writeFileSync(f, data);
    fs.readFileSync(f);
    fs.unlinkSync(f);
  }
  fs.rmdirSync(dir);
  return numFiles;
}

function memBench(sizeMb) {
  const arr = new Float64Array((sizeMb * 1024 * 1024) / 8);
  for (let i = 0; i < arr.length; i++) arr[i] = i * 1.0001;
  let sum = 0;
  for (let i = 0; i < arr.length; i++) sum += arr[i];
  return sum;
}

function runBenchmark(scale = 1, tmpDir) {
  const results = {};
  results.cpu_primes_ms = time(() => primesBench(200000 * scale));
  results.crypto_sha256_ms = time(() => hashBench(200000 * scale));
  results.json_ms = time(() => jsonBench(200000 * scale));
  results.file_io_ms = time(() => fileIoBench(2000 * scale, tmpDir));
  results.mem_ms = time(() => memBench(64));

  const total = Object.values(results).reduce((a, b) => a + b, 0);

  return {
    node_version: process.version,
    platform: process.platform,
    arch: process.arch,
    cpus: os.cpus().length,
    cpu_model: (os.cpus()[0] || {}).model,
    total_mem_bytes: os.totalmem(),
    scale,
    results_ms: results,
    total_ms: total,
  };
}

module.exports = { runBenchmark };
