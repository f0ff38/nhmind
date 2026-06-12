#!/usr/bin/env node
/** Quick probe for api.devtools.acurast.com reachability (CI diagnostics). */
const apiUrl = process.env.ACURAST_DEVTOOLS_API_URL ?? "https://api.devtools.acurast.com";

const paths = ["/", "/health", "/v1/health", "/v1/auth/view-key"];

for (const path of paths) {
  const url = `${apiUrl}${path}`;
  try {
    const res = await fetch(url, {
      method: path.includes("view-key") ? "POST" : "GET",
      headers: path.includes("view-key")
        ? { "Content-Type": "application/json" }
        : undefined,
      body: path.includes("view-key") ? JSON.stringify({ jobId: "0" }) : undefined,
    });
    const text = await res.text();
    console.log(`${res.status} ${url} ${text.slice(0, 80).replace(/\s+/g, " ")}`);
  } catch (error) {
    console.log(`ERR ${url} ${error instanceof Error ? error.message : String(error)}`);
  }
}
