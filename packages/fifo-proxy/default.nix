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
      };

      const requester = targetUrl.protocol === "https:" ? https : http;
      const proxyReq = requester.request(options, (proxyRes) => {
        res.writeHead(proxyRes.statusCode, proxyRes.headers);
        proxyRes.pipe(res);
        proxyRes.on("end", () => {
          t.inFlight--;
          processQueue(id);
        });
      });

      proxyReq.on("error", (err) => {
        try { res.writeHead(502, { "Content-Type": "text/plain" }); } catch {}
        try { res.end("Proxy error: " + err.message); } catch {}
        t.inFlight--;
        processQueue(id);
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

      // Determine which target this request is for from the URL prefix
      const parts = req.url.split("/").filter(Boolean);
      if (parts.length === 0) {
        res.writeHead(400);
        res.end("No provider id in path");
        return;
      }
      const id = parts[0];

      const t = targets.get(id);
      if (!t || !t.target) {
        res.writeHead(502);
        res.end("Unknown provider: " + id + " (not registered)");
        return;
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
