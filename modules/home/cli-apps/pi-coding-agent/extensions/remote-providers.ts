/**
 * Remote Provider Discovery Extension
 *
 * Auto-discovers models from remote OpenAI-compatible providers at startup.
 * Reads provider configs from ~/.pi/agent/models.json — any provider with
 * a baseUrl/api set but no models list gets models discovered dynamically
 * via GET /v1/models.
 *
 * API keys are handled via pi's /login — no need to store them in config.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { join } from "node:path";
import { getAgentDir } from "@earendil-works/pi-coding-agent";
import { existsSync, readFileSync } from "node:fs";
import { URL } from "node:url";
/** Providers that support -flex variants (NeuralWatt) */
const FLEX_PROVIDERS = new Set(["neuralwatt"]);

/**
 * Resolve an API key for a provider, checking multiple sources in order:
 * 1. The provider config value from models.json
 * 2. Auth.json (stored by /login)
 * 3. Environment variable named `<PROVIDER>_API_KEY` (uppercased)
 */
function resolveApiKey(providerName: string, configKey: string | undefined): string | undefined {
	if (configKey && configKey !== "placeholder") {
		return configKey;
	}
	// Check auth.json (stored by /login)
	const authPath = join(getAgentDir(), "auth.json");
	try {
		if (existsSync(authPath)) {
			const auth = JSON.parse(readFileSync(authPath, "utf-8"));
			const entry = auth[providerName];
			if (entry?.type === "api_key" && entry?.key) {
				return entry.key;
			}
		}
	} catch {}
	// Check environment variable
	const envVar = `${providerName.toUpperCase().replace(/[^A-Z0-9]/g, "_")}_API_KEY`;
	if (typeof process !== "undefined" && process.env?.[envVar]) {
		return process.env[envVar];
	}
	return undefined;
}

async function discoverModels(baseUrl: string, apiKey?: string): Promise<any[]> {
	const url = `${baseUrl.replace(/\/+$/, "")}/models`;
	const headers: Record<string, string> = {};
	if (apiKey) {
		headers["Authorization"] = `Bearer ${apiKey}`;
	}
	const res = await fetch(url, { signal: AbortSignal.timeout(10_000), headers });
	if (!res.ok) throw new Error(`GET ${url} returned ${res.status}`);
	const data = await res.json();
	return data.data ?? [];
}

export default async function (pi: ExtensionAPI) {
	const modelsPath = join(getAgentDir(), "models.json");

	if (!existsSync(modelsPath)) {
		console.log("[discovery] No models.json found");
		return;
	}

	let config: any;
	try {
		config = JSON.parse(readFileSync(modelsPath, "utf-8"));
	} catch (err) {
		console.log(`[discovery] Failed to parse models.json: ${err}`);
		return;
	}

	const providers = config.providers ?? {};
	const entries = Object.entries(providers) as Array<[string, any]>;

	for (const [name, provider] of entries) {
		if (!provider.baseUrl || !provider.api) continue;
		if (provider.api !== "openai-completions") continue;

		const apiKey = resolveApiKey(name, provider.apiKey);

		// Step 1: try discovery without auth (some providers work fine this way)
		let lastErr: unknown;
		let models: any[] = [];
		try {
			models = await discoverModels(provider.baseUrl);
		} catch (err) {
			lastErr = err;
			if (apiKey && String(err).includes("402")) {
				console.log(`[discovery] ${name}: 402 (auth required), retrying with api key`);
				try {
					models = await discoverModels(provider.baseUrl, apiKey);
					lastErr = undefined;
				} catch (err2) {
					lastErr = err2;
				}
			}
		}

		if (lastErr) {
			console.log(`[discovery] ${name}: failed — ${lastErr}`);
			try { pi.unregisterProvider(name); } catch {}
			pi.registerProvider(name, {
				baseUrl: provider.baseUrl,
				apiKey: apiKey ?? "placeholder",
				api: provider.api,
				models: [{
					id: `${name}/pending-discovery`,
					name: `${name} (login to discover models)`,
					reasoning: false,
					input: ["text"],
					cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
					contextWindow: 4096,
					maxTokens: 1024,
				}],
			});
			continue;
		}

		if (models.length === 0) {
			console.log(`[discovery] ${name}: no models found at ${provider.baseUrl}`);
			try { pi.unregisterProvider(name); } catch {}
			pi.registerProvider(name, {
				baseUrl: provider.baseUrl,
				apiKey: apiKey ?? "placeholder",
				api: provider.api,
				models: [{
					id: `${name}/pending-discovery`,
					name: `${name} (no models returned)`,
					reasoning: false,
					input: ["text"],
					cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
					contextWindow: 4096,
					maxTokens: 1024,
				}],
			});
			continue;
		}

		const capByName = (m: any) => m["metadata"]?.["capabilities"] ?? {};
		const pricing = (m: any) => m["metadata"]?.["pricing"] ?? {};
		const ctx = (m: any) =>
			m["context_length"] ??
			m["max_model_len"] ??
			m["max_context_window"] ??
			m["metadata"]?.["limits"]?.["max_context_length"] ??
			m["meta"]?.["n_ctx"] ??
			m["meta"]?.["n_ctx_train"] ??
			128000;
		const input = (m: any) => capByName(m)["vision"] ? ["text", "image"] : ["text"];
		const providerReasoning = provider.reasoning === true;

		const buildModelDef = (m: any, suffix = "", flex = false) => {
			const caps = capByName(m);
			const p = pricing(m);
			const meta = m["metadata"] ?? {};
			const isReasoning = caps["reasoning"] || caps["reasoning_effort"] || providerReasoning;
			return {
				id: m.id + suffix,
				name: (meta["display_name"] ?? m.id) + (suffix ? " (flex)" : ""),
				reasoning: isReasoning,
				thinkingLevelMap: isReasoning
					? { off: null, minimal: "low", low: "low", medium: "medium", high: "high" }
					: undefined,
				input: input(m),
				cost: {
					input: ((p["input_per_million"] ?? 0) * (flex ? 0.65 : 1)) / 1_000_000,
					output: ((p["output_per_million"] ?? 0) * (flex ? 0.65 : 1)) / 1_000_000,
					cacheRead: ((p["cached_input_per_million"] ?? 0) * (flex ? 0.65 : 1)) / 1_000_000,
					cacheWrite: 0,
				},
				contextWindow: ctx(m),
				maxTokens: 16384,
				compat: {
					supportsDeveloperRole: false,
				},
			};
		};

		const allModels = [
			...models.map((m: any) => buildModelDef(m)),
			...(FLEX_PROVIDERS.has(name)
				? models.map((m: any) => buildModelDef(m, "-flex", true))
				: []),
		];

		// If maxConcurrency is set, register with the shared FIFO proxy
		let effectiveBaseUrl = provider.baseUrl;
		const maxConcurrency = provider.maxConcurrency;
		if (typeof maxConcurrency === "number" && maxConcurrency > 0) {
			const proxyBase = "http://127.0.0.1:3080";
			const origUrl = new URL(provider.baseUrl);
			effectiveBaseUrl = proxyBase + "/" + name + origUrl.pathname;
			try {
				await fetch(proxyBase + "/__register", {
					method: "POST",
					headers: { "Content-Type": "application/json" },
					body: JSON.stringify({ id: name, target: provider.baseUrl, concurrency: maxConcurrency }),
					signal: AbortSignal.timeout(5_000),
				});
				console.log(`[discovery] ${name}: registered with queue proxy (concurrency=${maxConcurrency})`);
			} catch (err) {
				console.log(`[discovery] ${name}: queue proxy registration failed — ${err}`);
			}
		}

		try { pi.unregisterProvider(name); } catch {}
		pi.registerProvider(name, {
			baseUrl: effectiveBaseUrl,
			apiKey: apiKey ?? "placeholder",
			api: provider.api,
			models: allModels,
		});

		console.log(`[discovery] ${name}: registered ${allModels.length} models` + (effectiveBaseUrl !== provider.baseUrl ? ` via queue proxy` : ""));
	}
}
