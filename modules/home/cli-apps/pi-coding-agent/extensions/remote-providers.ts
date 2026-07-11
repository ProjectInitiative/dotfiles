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

async function discoverModels(baseUrl: string): Promise<Array<{ id: string }>> {
	const url = `${baseUrl.replace(/\/+$/, "")}/models`;
	const res = await fetch(url, { signal: AbortSignal.timeout(10_000) });
	if (!res.ok) throw new Error(`GET ${url} returned ${res.status}`);
	const data = await res.json();
	return (data.data ?? []).map((m: any) => ({ id: m.id }));
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
		// Skip providers that already have models listed
		if (provider.models && provider.models.length > 0) continue;
		// Need at least baseUrl and api to discover
		if (!provider.baseUrl || !provider.api) continue;
		if (provider.api !== "openai-completions") continue;

		try {
			const models = await discoverModels(provider.baseUrl);
			if (models.length === 0) {
				console.log(`[discovery] ${name}: no models found at ${provider.baseUrl}`);
				continue;
			}

			pi.registerProvider(name, {
				baseUrl: provider.baseUrl,
				apiKey: provider.apiKey ?? "placeholder",
				api: provider.api,
				models: models.map((m: any) => ({
					id: m.id,
					name: m.id,
					contextWindow: 128000,
					maxTokens: 16384,
				})),
			});

			console.log(`[discovery] ${name}: registered ${models.length} models`);
		} catch (err) {
			console.log(`[discovery] ${name}: failed — ${err}`);
		}
	}
}
