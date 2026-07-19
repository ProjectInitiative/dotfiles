# LLM Gateway / Proxy Research

> K8s-native alternatives for multi-provider LLM routing with central API key management.
> Context: replacing per-machine provider configs (pi's models.json) with a single cluster-wide proxy.
> LiteLLM dropped due to [March 2026 PyPI supply chain compromise](https://docs.litellm.ai/blog/security-update-march-2026).

---

## Requirements

- Self-hosted on existing K8s cluster
- Multi-provider routing (cheapestinference, neuralwatt, local llama.cpp, etc.)
- Central API key management (set keys once, issue virtual keys per machine/user)
- Rate limiting / concurrency control per provider or per key
- OpenAI-compatible endpoint (pi just points `baseUrl` at one place)
- Custom / OpenAI-compatible provider endpoints (any provider with a `/v1` API)

---

## Candidates

### 1. Portkey AI Gateway

- **Language:** Go
- **Deployment:** Self-hosted OSS tier + managed option, Docker/K8s
- **Providers:** Multiple including custom OpenAI-compatible endpoints
- **Key management:** ✅ Virtual API keys with spend limits and rate limiting
- **Rate limiting:** ✅ Per-key, per-provider
- **Guardrails:** ✅ Built-in request/response filtering
- **Observability:** ✅ Prometheus metrics, audit logging, admin dashboard
- **Caching:** ✅ Semantic + exact-match caching
- **Maturity:** Enterprise company behind it, well-funded
- **Notes:** Strongest LiteLLM replacement. Go-based avoids Python supply chain risk.

**Verdict: Top candidate**

### 2. Inference Gateway

- **Language:** Go (~10MB binary)
- **Deployment:** K8s operator (reconciles a `Gateway` custom resource)
- **Providers:** OpenAI, Ollama, Groq, Cloudflare, Cohere, Anthropic, DeepSeek, Google, Mistral, + custom
- **Key management:** ❌ None — would need to layer on top
- **Rate limiting:** ❌ Not built-in
- **MCP support:** ✅ Built-in Model Context Protocol integration
- **Observability:** ✅ OpenTelemetry metrics
- **Maturity:** Active, ~2.5k stars, Apache 2.0 license
- **Notes:** Lightweight and K8s-native but missing key management and rate limiting. Best for organizations that already have API key infrastructure.

**Verdict: Needs additional tooling for key management**

### 3. Kong AI Gateway

- **Language:** Go / Lua (plugin system)
- **Deployment:** K8s native via Kong Ingress Controller
- **Providers:** Plugin-based, supports custom endpoints
- **Key management:** ✅ Via Kong plugins (key-auth, rate-limiting)
- **Rate limiting:** ✅ Native plugin
- **Maturity:** Very mature, battle-tested for traditional API Gateway, CNCF project
- **Notes:** If you already run Kong in the cluster, adding AI routing via plugins is natural. AI Gateway is a newer addition on top of their existing gateway.

**Verdict: Strong if already on Kong; overkill otherwise**

### 4. GoModel

- **Language:** Go
- **Deployment:** Single binary / Docker
- **Providers:** OpenAI, Anthropic, Gemini, Groq, Ollama, vLLM, OpenRouter, + custom
- **Key management:** ❌ Missing (v0.2.0 roadmap)
- **Rate limiting:** ❌ Missing (v0.2.0 roadmap)
- **Caching:** ✅ Two-layer (exact-match + semantic via vector DB)
- **Maturity:** Pre-1.0 (v0.1.20), 493 stars, small opaque Polish team
- **Notes:** Simple deployment but missing production features. No virtual keys yet. Pre-1.0.

**Verdict: Too immature for production**

### 5. llm-d Router (K8s SIG)

- **Language:** Go
- **Deployment:** K8s native, integrates with Gateway API + Envoy
- **Providers:** Self-hosted models (vLLM etc.) — not a multi-provider SaaS proxy
- **Key management:** ❌ Not applicable
- **Rate limiting:** ❌ Not applicable
- **Focus:** KV-cache aware routing, disaggregated serving, inference optimization
- **Maturity:** GA, K8s SIG project
- **Notes:** This is for routing to YOUR models across GPU nodes, not for proxying SaaS providers. Complementary to a gateway, not a replacement.

**Verdict: Not what we need (different use case)**

---

## Current setup (for reference)

We currently have:

1. **fifo-proxy** — local FIFO queue proxy on port 3080, deployed via systemd user service. Auto-registers unknown providers with a default target. Handles cheapestinference's 1-concurrent-request limit. Works but is per-machine.

2. **remote-providers.ts** — pi extension that reads models.json and registers providers with pi at startup. Rewrites baseUrl to point through fifo-proxy when `maxConcurrency` is set.

3. **models.json** — provider configs managed by Nix (ai/default.nix). Each machine has its own copy with its own API keys.

An ideal gateway would replace the per-machine models.json with a single cluster endpoint. Pi would have one provider entry pointing at the gateway, and the gateway would route to cheapestinference, neuralwatt, astrolabe, etc.

---

## Notes

- LiteLLM's supply chain compromise (March 2026) was a PyPI package takeover via their CI/CD pipeline. Versions before v1.83.0 were affected.
- Any Python-based gateway inherits the same PyPI supply chain risk. Go-based alternatives avoid this attack surface entirely.
- The fifo-proxy we built is intentionally minimal — just FIFO queuing. A full gateway like Portkey would replace it entirely.
