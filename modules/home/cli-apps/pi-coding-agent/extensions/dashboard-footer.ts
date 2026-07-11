/**
 * Dashboard Footer Extension — live TPS/TFT tracking with real-time updates
 *
 * Shows:
 *   ↑Nk ↓Nk R Nk  |  TPS N  TFT Nms  |  model (branch)
 *
 * TPS updates LIVE during streaming by counting tokens from the accumulated
 * message content on each `message_update` event, throttled to ~5fps.
 * Stats persist across turns so there's no flicker.
 *
 * Commands:
 *   /dashboard     — Toggle custom dashboard footer on/off (default: on)
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

// ─── Turn timing (live) ──────────────────────────────────────────────────────

let turnStart = 0;
let firstTokenTime = 0;
let liveTokens = 0;         // accumulated tokens during streaming
let liveTft = 0;            // ms — updates after first token
let liveTps = 0;            // tokens/sec — updates every 200ms during streaming
let lastUpdateTime = 0;
let requestRender: (() => void) | null = null;

// ─── Retry timer ────────────────────────────────────────────────────────────

let retryAttempt = 0;
let retryMaxAttempts = 0;
let retryDelayMs = 0;
let retryStartTime = 0;
let retryErrorMessage = "";

// ─── Persisted stats (last completed turn) ───────────────────────────────────
// These stay visible until a new turn produces its first token.

let lastTurnTft = 0;
let lastTurnTps = 0;
let contextWindowSize = 0;

// ─── Throttle — limit re-renders to ~5fps ────────────────────────────────────

const THROTTLE_MS = 200;

// ─── Token estimation ────────────────────────────────────────────────────────
// Rough: ~4 chars per token for English text. Good enough for live display.

function estimateTokens(text: string): number {
	return Math.max(1, Math.round(text.length / 4));
}

function countMessageTokens(msg: { content?: Array<{ type: string; text?: string }> }): number {
	let total = 0;
	for (const c of msg.content || []) {
		if (c.type === "text" && c.text) total += estimateTokens(c.text);
	}
	return total;
}

// ─── Formatter ───────────────────────────────────────────────────────────────

function fmt(n: number): string {
	if (n < 1000) return `${n}`;
	if (n < 10_000) return `${(n / 1000).toFixed(1)}k`;
	if (n < 1_000_000) return `${Math.round(n / 1000)}k`;
	return `${(n / 1_000_000).toFixed(1)}M`;
}

let enabled = true;

export default function (pi: ExtensionAPI) {
	// ── Turn lifecycle ────────────────────────────────────────────────────────
	pi.on("turn_start", async () => {
		turnStart = Date.now();
		firstTokenTime = 0;
		liveTokens = 0;
		liveTft = 0;
		liveTps = 0;
	});

	// ── Live TPS during streaming ─────────────────────────────────────────────
	pi.on("message_update", async (event) => {
		// Track time to first token
		if (firstTokenTime === 0) {
			firstTokenTime = Date.now();
			liveTft = firstTokenTime - turnStart;

			// Force immediate render to show TFT as soon as first token arrives
			lastUpdateTime = 0; // ensure throttle passes
		}

		// Count tokens from accumulated message content
		liveTokens = countMessageTokens(event.message);

		// Throttled: update TPS and request footer re-render at ~5fps
		const now = Date.now();
		if (now - lastUpdateTime >= THROTTLE_MS) {
			const elapsed = now - turnStart;
			liveTps = elapsed > 0 ? Math.round((liveTokens / elapsed) * 1000) : 0;
			lastUpdateTime = now;
			requestRender?.();
		}
	});

	// ── Freeze on completion ──────────────────────────────────────────────────
	pi.on("message_end", async (event) => {
		if (event.message.role === "assistant") {
			const elapsed = Date.now() - turnStart;
			const msg = event.message as AssistantMessage;
			const output = msg.usage?.output || liveTokens;

			lastTurnTft = firstTokenTime > 0 ? firstTokenTime - turnStart : 0;
			lastTurnTps = elapsed > 0 ? Math.round((output / elapsed) * 1000) : 0;

			// Sync live values to final
			liveTft = lastTurnTft;
			liveTps = lastTurnTps;

			// Force final render with accurate numbers
			requestRender?.();
		}
	});

	// ── Toggle command ────────────────────────────────────────────────────────
	pi.registerCommand("dashboard", {
		description: "Toggle custom dashboard footer",
		handler: async (_args, ctx) => {
			enabled = !enabled;
			if (!enabled) {
				ctx.ui.setFooter(undefined);
				ctx.ui.notify("Default footer restored", "info");
			} else {
				ctx.ui.notify("Dashboard footer enabled", "info");
				installFooter(ctx);
			}
		},
	});

	// ── Install footer ────────────────────────────────────────────────────────
	pi.on("auto_retry_start", async (event: any) => {
		retryAttempt = event.attempt;
		retryMaxAttempts = event.maxAttempts;
		retryDelayMs = event.delayMs;
		retryStartTime = Date.now();
		retryErrorMessage = event.errorMessage || "";
		requestRender?.();
	});

	pi.on("auto_retry_end", async () => {
		retryAttempt = 0;
		retryMaxAttempts = 0;
		retryDelayMs = 0;
		retryStartTime = 0;
		retryErrorMessage = "";
		requestRender?.();
	});

	pi.on("session_start", async (_event, ctx) => {
		if (enabled) installFooter(ctx);
	});

	function installFooter(ctx: any) {
		ctx.ui.setFooter((tui: any, theme: any, footerData: any) => {
			// Store render function so message_update can trigger re-renders
			requestRender = () => tui.requestRender();

			const unsub = footerData.onBranchChange(() => tui.requestRender());

			return {
				dispose: () => {
					unsub();
					requestRender = null;
				},
				invalidate() {},
				render(width: number): string[] {
					const lines: string[] = [];

					// ── Line 1: pwd + git branch ──────────────────────────────
					const dir = ctx.sessionManager.getCwd();
					const branch = footerData.getGitBranch();
					const dirStr = branch ? `${dir} (${branch})` : dir;
					lines.push(truncateToWidth(theme.fg("dim", dirStr), width));

					// ── Line 2: stats ──────────────────────────────────────────
					const parts: string[] = [];

					// Token stats (cumulative across session) — dimmed, less important
					let input = 0, output = 0, cacheRead = 0;
					for (const e of ctx.sessionManager.getBranch()) {
						if (e.type === "message" && e.message.role === "assistant") {
							const m = e.message as AssistantMessage;
							input += m.usage.input;
							output += m.usage.output;
							cacheRead += m.usage.cacheRead;
						}
					}

					const dim = (s: string) => theme.fg("dim", s);
					parts.push(dim(`↑${fmt(input)}`));
					parts.push(dim(`↓${fmt(output)}`));
					if (cacheRead) parts.push(dim(`R${fmt(cacheRead)}`));

					// Separator
					parts.push(dim(`│`));

					// Context usage — actual tokens + percentage
					const ctxUsage = ctx.getContextUsage();
					if (ctxUsage?.contextWindow) {
						contextWindowSize = ctxUsage.contextWindow;
						const pct = ctxUsage.percent ?? 0;
						const tokens = ctxUsage.tokens ?? 0;
						let colored: string;
						if (pct > 90) colored = theme.fg("error", `${fmt(tokens)} (${pct.toFixed(1)}%)`);
						else if (pct > 70) colored = theme.fg("warning", `${fmt(tokens)} (${pct.toFixed(1)}%)`);
						else colored = `${fmt(tokens)} (${pct.toFixed(1)}%)`;
						parts.push(colored);
					}

					// Live TPS/TFT (during streaming) or last completed turn's stats.
					// Never shows "waiting..." — the previous turn's stats persist
					// until the current streaming turn produces its first token.
					const showTft = liveTft > 0 ? liveTft : lastTurnTft;
					const showTps = liveTps > 0 ? liveTps : lastTurnTps;

					if (showTft > 0) {
						parts.push(dim(`│`));
						if (showTps > 0) parts.push(dim(`TPS ${showTps}`));
						const tftSec = (showTft / 1000).toFixed(1);
						parts.push(dim(`TFT ${tftSec}s`));
					}

					// Retry countdown — shows when pi is auto-retrying after a 429 or other error
					if (retryAttempt > 0 && retryMaxAttempts > 0) {
						const elapsed = Date.now() - retryStartTime;
						const remaining = Math.max(0, Math.ceil((retryDelayMs - elapsed) / 1000));
						parts.push(dim(`│`));
						parts.push(theme.fg("warning", `⏳ retry ${retryAttempt}/${retryMaxAttempts} ${remaining}s`));
					}

					// Right-aligned model name + context window size
					const modelStr = ctx.model?.id
						? contextWindowSize > 0
							? `${ctx.model.id} ${fmt(contextWindowSize)}`
							: ctx.model.id
						: "no-model";

					const leftRaw = parts.join(" ");
					const leftWidth = visibleWidth(leftRaw);
					const rightRaw = theme.fg("dim", modelStr);
					const rightWidth = visibleWidth(rightRaw);
					const pad = Math.max(2, width - leftWidth - rightWidth);

					lines.push(leftRaw + " ".repeat(pad) + rightRaw);

					return lines;
				},
			};
		});
	}
}
