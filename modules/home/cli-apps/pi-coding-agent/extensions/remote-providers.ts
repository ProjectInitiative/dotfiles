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
import { existsSync, readFileSync, writeFileSync } from "node:fs";

/** Providers that support -flex variants (NeuralWatt) */
const FLEX_PROVIDERS = new Set(["neuralwatt"]);

async function discoverModels(baseUrl: string): Promise<any[]> {
	const url = `${baseUrl.replace(/\/+$/, "")}/models`;
	const res = await fetch(url, { signal: AbortSignal.timeout(10_000) });
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
		// Skip providers that already explicitly opt out of discovery
		// (models list with real models selected by user)
		if (!provider.baseUrl || !provider.api) continue;
		if (provider.api !== "openai-completions") continue;

		try {
			const models = await discoverModels(provider.baseUrl);
			if (models.length === 0) {
				console.log(`[discovery] ${name}: no models found at ${provider.baseUrl}`);
				continue;
			}

			// QuickJS doesn't support dot notation on snake_case JSON keys.
			// Always use bracket notation for API response properties.
			const capByName = (m: any) => m["metadata"]?.["capabilities"] ?? {};
			const pricing = (m: any) => m["metadata"]?.["pricing"] ?? {};
			const ctx = (m: any) => m["max_model_len"] ?? m["metadata"]?.["limits"]?.["max_context_length"] ?? 128000;
			const input = (m: any) => capByName(m)["vision"] ? ["text", "image"] : ["text"];

			const buildModelDef = (m: any, suffix = "", flex = false) => {
				const caps = capByName(m);
				const p = pricing(m);
				const meta = m["metadata"] ?? {};
				return {
					id: m.id + suffix,
					name: (meta["display_name"] ?? m.id) + (suffix ? " (flex)" : ""),
					reasoning: caps["reasoning"] ?? false,
					thinkingLevelMap: caps["reasoning"] || caps["reasoning_effort"]
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
				};
			};

			const allModels = [
				...models.map((m: any) => buildModelDef(m)),
				...(FLEX_PROVIDERS.has(name)
					? models.map((m: any) => buildModelDef(m, "-flex", true))
					: []),
			];

			// Register provider with discovered models
			try { pi.unregisterProvider(name); } catch {}
			pi.registerProvider(name, {
				baseUrl: provider.baseUrl,
				apiKey: provider.apiKey ?? "placeholder",
				api: provider.api,
				models: allModels,
			});

			console.log(`[discovery] ${name}: registered ${allModels.length} models`);
		} catch (err) {
			console.log(`[discovery] ${name}: failed — ${err}`);
		}
	}
}
