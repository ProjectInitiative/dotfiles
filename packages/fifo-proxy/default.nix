# FIFO queue proxy — shared proxy with per-target queues.
# Providers register with a target URL + concurrency limit.
# The proxy maintains one independent FIFO queue per target.
# Requests are routed by path prefix: /<provider-id>/...
#
# Usage:
#   fifo-proxy [--port 3080]
#
# Extensions configure it via POST /__register:
#   curl -X POST http://localhost:3080/__register \
#     -H "Content-Type: application/json" \
#     -d '{"id":"cheapestinference","target":"https://api.cheapestinference.com/v1","concurrency":1}'
#
# Then requests to http://localhost:3080/cheapestinference/v1/chat/completions
# get queued per-target and forwarded.

{ writeShellScriptBin, nodejs_latest, lib }:

writeShellScriptBin "fifo-proxy" ''
  exec ${lib.getExe nodejs_latest} -e '
    const http = require("http");
    const https = require("https");
    const { URL } = require("url");

    const PORT = (() => {
      for (const a of process.argv) {
        if (a.startsWith("--port=")) return parseInt(a.split("=")[1], 10);
        if (a === "--port" && process.argv[process.argv.indexOf(a) + 1]) {
          return parseInt(process.argv[process.argv.indexOf(a) + 1], 10);
        }
      }
      return 3080;
    })();

    const DEFAULT_TARGET = (() => {
      for (const a of process.argv) {
        if (a.startsWith("--default-target=")) return a.split("=").slice(1).join("=");
        if (a === "--default-target" && process.argv[process.argv.indexOf(a) + 1]) {
          return process.argv[process.argv.indexOf(a) + 1];
        }
      }
      return "https://api.cheapestinference.com/v1";
    })();
    console.log("[fifo] default target: " + DEFAULT_TARGET);

    // Registered targets: Map<id, { target: URL, concurrency: number, queue: [], inFlight: number }>
    const targets = new Map();

    function getQueue(id) {
      let t = targets.get(id);
      if (!t) {
        t = { target: null, concurrency: 0, queue: [], inFlight: 0 };
        targets.set(id, t);
      }
      return t;
    }

    function processQueue(id) {
      const t = targets.get(id);
      if (!t || !t.target) return;
      while (t.inFlight < t.concurrency && t.queue.length > 0) {
        const entry = t.queue.shift();
        forward(id, entry);
      }
    }

    const REQUEST_TIMEOUT = (() => {
      for (const a of process.argv) {
        if (a.startsWith("--timeout=")) return parseInt(a.split("=")[1], 10);
        if (a === "--timeout" && process.argv[process.argv.indexOf(a) + 1]) {
          return parseInt(process.argv[process.argv.indexOf(a) + 1], 10);
        }
      }
      return 60_000;
    })();
    console.log("[fifo] request timeout: " + REQUEST_TIMEOUT + "ms");

    // Safely decrement in-flight and drain next queued request
    function releaseInflight(id) {
      const t = targets.get(id);
      if (t && t.inFlight > 0) {
        t.inFlight--;
        processQueue(id);
      }
    }

    function forward(id, { req, res }) {
      const t = targets.get(id);
      if (!t || !t.target) {
        res.writeHead(502);
        res.end("Unknown target: " + id);
        return;
      }
      t.inFlight++;
      const path = req.url;
      const targetUrl = t.target;

      // Strip the /<id> prefix from the path
      const strippedPath = path.replace(new RegExp("^/" + id.replace(/[.*+?^''${}()|[\]\\]/g, "\\$&")), "");

      const options = {
        hostname: targetUrl.hostname,
        port: targetUrl.port || (targetUrl.protocol === "https:" ? 443 : 80),
        path: strippedPath,
        method: req.method,
        headers: { ...req.headers, host: targetUrl.host },
        rejectUnauthorized: false,
        timeout: REQUEST_TIMEOUT,
      };

      const requester = targetUrl.protocol === "https:" ? https : http;
      let released = false;
      function safeRelease() {
        if (released) return;
        released = true;
        releaseInflight(id);
      }

      const proxyReq = requester.request(options, (proxyRes) => {
        res.writeHead(proxyRes.statusCode, proxyRes.headers);
        proxyRes.pipe(res);

        const onDone = () => safeRelease();
        proxyRes.on("end", onDone);
        proxyRes.on("close", onDone);
        proxyRes.on("error", (err) => {
          try { res.end(); } catch {}
          safeRelease();
        });
      });

      proxyReq.on("error", (err) => {
        try { res.writeHead(502, { "Content-Type": "text/plain" }); } catch {}
        try { res.end("Proxy error: " + err.message); } catch {}
        safeRelease();
      });

      // HTTP-level timeout — fires after the socket idle timeout above
      proxyReq.on("timeout", () => {
        proxyReq.destroy(new Error("Request timed out after " + REQUEST_TIMEOUT + "ms"));
      });

      req.pipe(proxyReq);
      req.on("error", () => proxyReq.destroy());
    }

    const server = http.createServer((req, res) => {
      // Registration endpoint
      if (req.method === "POST" && req.url === "/__register") {
        let body = "";
        req.on("data", (c) => body += c);
        req.on("end", () => {
          try {
            const cfg = JSON.parse(body);
            if (!cfg.id || !cfg.target) {
              res.writeHead(400);
              res.end("Missing id or target");
              return;
            }
            const targetUrl = new URL(cfg.target);
            const t = getQueue(cfg.id);
            t.target = targetUrl;
            t.concurrency = typeof cfg.concurrency === "number" ? cfg.concurrency : 1;
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ ok: true, id: cfg.id, target: cfg.target, concurrency: t.concurrency }));
            console.log("[fifo] registered " + cfg.id + " -> " + cfg.target + " (concurrency=" + t.concurrency + ")");
          } catch (e) {
            res.writeHead(400);
            res.end("Invalid JSON: " + e.message);
          }
        });
        return;
      }

      // Health check
      if (req.url === "/__health" || req.url === "/health") {
        const status = {};
        for (const [id, t] of targets) {
          status[id] = { concurrency: t.concurrency, inFlight: t.inFlight, queued: t.queue.length, target: t.target ? t.target.href : null };
        }
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ ok: true, uptime: process.uptime().toFixed(1) + "s", targets: status }));
        return;
      }

      // Determine which target this request is for from the URL prefix
      const parts = req.url.split("/").filter(Boolean);
      if (parts.length === 0) {
        res.writeHead(400);
        res.end("No provider id in path");
        return;
      }
      const id = parts[0];

      let t = targets.get(id);
      if (!t || !t.target) {
        // Auto-register with default target so it works without pre-registration
        const targetUrl = new URL(DEFAULT_TARGET);
        t = { target: targetUrl, concurrency: 1, queue: [], inFlight: 0 };
        targets.set(id, t);
        console.log("[fifo] auto-registered " + id + " -> " + DEFAULT_TARGET + " (concurrency=1)");
      }

      if (t.concurrency <= 0) {
        // No queuing — forward immediately
        forward(id, { req, res });
      } else {
        t.queue.push({ req, res });
        processQueue(id);
      }
    });

    server.listen(PORT, "127.0.0.1", () => {
      console.log("fifo-proxy listening on http://127.0.0.1:" + PORT);
      console.log("  Register targets via POST /__register");
    });
  ' "$@"
''
