# FIFO queue proxy — shared proxy with per-target queues.
# Providers register with a target URL + concurrency limit.
# The proxy maintains one independent FIFO queue per target.
# Requests are routed by path prefix: /<provider-id>/...
#
# Features:
#   - Per-provider FIFO queues with configurable concurrency
#   - Request timeout with automatic slot release
#   - Think-tag stripping (strips <think> from content when reasoning_content present)
#   - Auto-registration of unknown providers with default target
#   - Health endpoint at /__health
#   - Registration endpoint at POST /__register
#
# Usage:
#   fifo-proxy [--port 3080] [--timeout 60000] [--default-target https://...]

{ writeShellScriptBin, nodejs_latest, lib }:

writeShellScriptBin "fifo-proxy" ''
  exec ${lib.getExe nodejs_latest} -e '
    const http = require("http");
    const https = require("https");
    const { URL } = require("url");

    // ── CLI args ────────────────────────────────────────────────
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

    const REQUEST_TIMEOUT = (() => {
      for (const a of process.argv) {
        if (a.startsWith("--timeout=")) return parseInt(a.split("=")[1], 10);
        if (a === "--timeout" && process.argv[process.argv.indexOf(a) + 1]) {
          return parseInt(process.argv[process.argv.indexOf(a) + 1], 10);
        }
      }
      return 60_000;
    })();

    console.log("[fifo] listening on port " + PORT + ", timeout " + REQUEST_TIMEOUT + "ms, default target " + DEFAULT_TARGET);

    // ── Target registry ─────────────────────────────────────────
    // targets: Map<id, { target: URL, concurrency: number, queue: [], inFlight: number }>
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

    function releaseInflight(id) {
      const t = targets.get(id);
      if (t && t.inFlight > 0) {
        t.inFlight--;
        processQueue(id);
      }
    }

    // ── Think-tag stripping ─────────────────────────────────────
    // Cheapestinference duplicates thinking in both reasoning_content
    // AND wrapped in <think> tags inside content. Strip the latter.

    // Stateful think-tag tracking — <think> and </think> can span SSE chunks.
    // When reasoning_content is present, the content field is just a duplicate
    // of the thinking text. We suppress it until the first chunk that arrives
    // without reasoning_content, where we also strip any leftover </think> tags.
    const thinkState = { inThink: false };

    function stripChoiceThinkTags(obj) {
      if (!obj || !obj.choices) return false;
      let changed = false;
      for (const ch of obj.choices) {
        if (ch.delta) {
          const hasReasoning = !!(ch.delta.reasoning_content && typeof ch.delta.reasoning_content === "string" && ch.delta.reasoning_content.length > 0);

          if (hasReasoning) {
            // Content is just a duplicate of reasoning_content — suppress it
            if (ch.delta.content !== undefined && ch.delta.content !== "") {
              ch.delta.content = "";
              changed = true;
            }
            thinkState.inThink = true;
          } else if (thinkState.inThink && ch.delta.content) {
            // First content after reasoning — strip leftover </think> tags
            const stripped = ch.delta.content.replace(/^\s*<\/think>\s*/g, "");
            if (stripped !== ch.delta.content) {
              ch.delta.content = stripped;
              changed = true;
            }
            thinkState.inThink = false;
          }
        }
        if (ch.message) {
          if (ch.message.reasoning_content && ch.message.reasoning_content.length > 0 && ch.message.content) {
            const stripped = ch.message.content.replace(/<think>[\s\S]*?<\/think>/g, "");
            if (stripped !== ch.message.content) {
              ch.message.content = stripped;
              changed = true;
            }
          }
        }
      }
      return changed;
    }

    function stripThinkTags(line) {
      if (typeof line !== "string") return line;
      // SSE: data: {...}
      const m = line.match(/^data: (.+)/);
      if (m) {
        try {
          const parsed = JSON.parse(m[1]);
          if (stripChoiceThinkTags(parsed)) {
            return "data: " + JSON.stringify(parsed) + "\n\n";
          }
        } catch {}
        return line;
      }
      // Non-streaming JSON
      try {
        const parsed = JSON.parse(line);
        if (stripChoiceThinkTags(parsed)) {
          return JSON.stringify(parsed);
        }
      } catch {}
      return line;
    }

    // ── Request forwarding ──────────────────────────────────────
    function forward(id, { req, res }) {
      const t = targets.get(id);
      if (!t || !t.target) {
        res.writeHead(502);
        res.end("Unknown target: " + id);
        return;
      }
      t.inFlight++;
      const ts = new Date().toISOString().slice(11, 19);
      console.log("[fifo] " + ts + " " + id + " " + req.method + " " + req.url + " (inFlight=" + t.inFlight + ")");

      const path = req.url;
      const targetUrl = t.target;
      const strippedPath = path.replace(new RegExp("^/" + id.replace(/[.*+?^$()|[\]\\]/g, "\\$&")), "");
      const upstreamUrl = targetUrl.origin + strippedPath;

      let released = false;
      function safeRelease() {
        if (released) return;
        released = true;
        releaseInflight(id);
      }

      // Read the incoming request body
      const bodyChunks = [];
      req.on("data", (c) => bodyChunks.push(c));
      req.on("end", async () => {
        const reqBody = Buffer.concat(bodyChunks);
        const isTextBody = (req.headers["content-type"] || "").includes("application/json");

        try {
          const upstreamRes = await fetch(upstreamUrl, {
            method: req.method,
            headers: { ...req.headers, host: targetUrl.host },
            body: reqBody.length > 0 ? reqBody : undefined,
            signal: AbortSignal.timeout(REQUEST_TIMEOUT),
          });

          const ct = (upstreamRes.headers.get("content-type") || "").toLowerCase();
          const isStreaming = ct.includes("text/event-stream");

          if (isStreaming) {
            // ── Streaming (SSE) ───────────────────────────────────
            // Forward status + headers (fetch already decompressed)
            const outHeaders = {};
            upstreamRes.headers.forEach((v, k) => { outHeaders[k] = v; });
            delete outHeaders["content-length"];
            delete outHeaders["transfer-encoding"];
            delete outHeaders["content-encoding"];
            res.writeHead(upstreamRes.status, outHeaders);

            // Process the decompressed stream incrementally for real-time SSE
            const reader = upstreamRes.body.getReader();
            const decoder = new TextDecoder();
            let buf = "";
            function pumpStream() {
              reader.read().then(({ done, value }) => {
                if (done) {
                  if (buf.trim().length > 0) {
                    const trimmed = buf.trim();
                    const result = stripThinkTags(trimmed);
                    res.write(result !== trimmed ? result : trimmed + "\n\n");
                  }
                  res.end();
                  safeRelease();
                  return;
                }
                buf += decoder.decode(value, { stream: true });
                const parts = buf.split("\n\n");
                buf = parts.pop() || "";
                for (const part of parts) {
                  const trimmed = part.trim();
                  if (trimmed.length === 0) continue;
                  const result = stripThinkTags(trimmed);
                  if (result !== trimmed) {
                    res.write(result);
                  } else {
                    res.write(trimmed + "\n\n");
                  }
                }
                pumpStream();
              }).catch((err) => {
                try { res.end(); } catch {}
                safeRelease();
              });
            }
            pumpStream();
          } else {
            // ── Non-streaming ─────────────────────────────────────
            const text = await upstreamRes.text(); // Already decompressed by fetch
            const result = isTextBody ? stripThinkTags(text) : text;
            const outHeaders = { "content-type": ct || "application/octet-stream" };
            res.writeHead(upstreamRes.status, outHeaders);
            res.end(result);
          }
        } catch (err) {
          try { res.writeHead(502, { "Content-Type": "text/plain" }); } catch {}
          try { res.end("Proxy error: " + (err.message || err)); } catch {}
        }
        safeRelease();
      });
      req.on("error", () => {});
    }

    // ── HTTP server ─────────────────────────────────────────────
    const server = http.createServer((req, res) => {
      // POST /__register — register a provider
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

      // GET /__health — health check
      if (req.url === "/__health" || req.url === "/health") {
        const status = {};
        for (const [id, t] of targets) {
          status[id] = {
            concurrency: t.concurrency,
            inFlight: t.inFlight,
            queued: t.queue.length,
            target: t.target ? t.target.href : null,
          };
        }
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ ok: true, uptime: process.uptime().toFixed(1) + "s", targets: status }));
        return;
      }

      // ── Route by path prefix ──────────────────────────────────
      const parts = req.url.split("/").filter(Boolean);
      if (parts.length === 0) {
        res.writeHead(400);
        res.end("No provider id in path");
        return;
      }
      const id = parts[0];

      let t = targets.get(id);
      if (!t || !t.target) {
        const targetUrl = new URL(DEFAULT_TARGET);
        t = { target: targetUrl, concurrency: 1, queue: [], inFlight: 0 };
        targets.set(id, t);
        console.log("[fifo] auto-registered " + id + " -> " + DEFAULT_TARGET + " (concurrency=1)");
      }

      if (t.concurrency <= 0) {
        forward(id, { req, res });
      } else {
        t.queue.push({ req, res });
        processQueue(id);
      }
    });

    server.listen(PORT, "127.0.0.1", () => {
      console.log("[fifo] listening on http://127.0.0.1:" + PORT);
      console.log("[fifo] register targets via POST /__register");
    });
  ' "$@"
''
