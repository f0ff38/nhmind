import http from "node:http";
import WebSocket from "ws";

const RELAY_WS = process.env.RELAY_WS_URL ?? "ws://relay:8080";
const PORT = Number(process.env.PORT ?? 8090);
const TIMEOUT_MS = Number(process.env.REQUEST_TIMEOUT_MS ?? 15_000);

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function relayOverWebSocket(message) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(RELAY_WS);
    const lines = [];
    let settled = false;

    const finish = (result) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
        ws.close();
      }
      resolve(result);
    };

    const timer = setTimeout(() => finish(lines.join("\n")), TIMEOUT_MS);

    ws.on("open", () => {
      ws.send(JSON.stringify(message));
    });

    ws.on("message", (data) => {
      const line = data.toString();
      lines.push(line);
      try {
        const parsed = JSON.parse(line);
        const kind = parsed[0];
        if (message[0] === "EVENT" && kind === "OK") {
          finish(lines.join("\n"));
          return;
        }
        if (message[0] === "REQ" && kind === "EOSE") {
          finish(lines.join("\n"));
        }
      } catch {
        // Ignore non-JSON relay frames.
      }
    });

    ws.on("error", (err) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        reject(err);
      }
    });

    ws.on("close", () => finish(lines.join("\n")));
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method !== "POST") {
    res.writeHead(405, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("POST only");
    return;
  }

  let message;
  try {
    message = JSON.parse(await readBody(req));
  } catch {
    res.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("invalid json");
    return;
  }

  if (!Array.isArray(message) || typeof message[0] !== "string") {
    res.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("expected nostr protocol array");
    return;
  }

  try {
    const payload = await relayOverWebSocket(message);
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(payload);
  } catch (error) {
    const details = error instanceof Error ? error.message : String(error);
    res.writeHead(502, { "Content-Type": "text/plain; charset=utf-8" });
    res.end(details);
  }
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`http-bridge listening on :${PORT} -> ${RELAY_WS}`);
});
