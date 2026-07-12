/**
 * Custom Tool Renderer — clean, subtle, no bright colors
 *
 * All tools use renderShell: "self" so there's no bright outer box/header.
 * Invocations: bold name + dim args (one line).
 * In-progress: muted "reading…", "running…".
 * Completed: dim summary.
 * Expanded: syntax-highlighted code / colored diff.
 *
 * Remove this extension file and /reload to restore pi's default rendering.
 */

import type { BashToolDetails, EditToolDetails, ExtensionAPI, ReadToolDetails } from "@earendil-works/pi-coding-agent";
import { createBashTool, createEditTool, createReadTool, createWriteTool, getLanguageFromPath, highlightCode } from "@earendil-works/pi-coding-agent";
import { Text, truncateToWidth } from "@earendil-works/pi-tui";

export default function (pi: ExtensionAPI) {
	const cwd = process.cwd();

	// ── Style helpers ─────────────────────────────────────────────────────────

	function muted(s: string, theme: any) {
		return theme.fg("muted", s);
	}
	function dim(s: string, theme: any) {
		return theme.fg("dim", s);
	}
	function bold(s: string, theme: any) {
		return theme.bold(s);
	}
	// Action label: accent (blue-ish) for read/write/edit
	function action(s: string, theme: any) {
		return theme.fg("toolTitle", theme.bold(s));
	}
	// Prompt label: green for bash $
	function prompt(s: string, theme: any) {
		return theme.fg("success", theme.bold(s));
	}

	// ── Read tool ─────────────────────────────────────────────────────────────
	const originalRead = createReadTool(cwd);
	pi.registerTool({
		name: "read",
		label: "read",
		description: originalRead.description,
		parameters: originalRead.parameters,
		renderShell: "self",

		async execute(toolCallId, params, signal, onUpdate) {
			return originalRead.execute(toolCallId, params, signal, onUpdate);
		},

		renderCall(args, theme) {
			// Blue accent = pending/in-progress
			let text = theme.fg("accent", `read ${args.path}`);
			if (args.offset || args.limit) {
				const parts: string[] = [];
				if (args.offset) parts.push(`offset=${args.offset}`);
				if (args.limit) parts.push(`limit=${args.limit}`);
				text += dim(` (${parts.join(", ")})`, theme);
			}
			return new Text(text, 0, 0);
		},

		renderResult(result, { expanded, isPartial }, theme) {
			if (isPartial) return new Text(muted("reading…", theme), 0, 0);

			const details = result.details as ReadToolDetails | undefined;
			const content = result.content[0];
			const path = details?.path || "";

			if (content?.type === "image") {
				return new Text(dim("Image loaded", theme), 0, 0);
			}
			if (content?.type !== "text") {
				return new Text(theme.fg("error", "No content"), 0, 0);
			}

			const lines = content.text.split("\n");
			const lineCount = lines.length;
			let text = dim(`${lineCount} lines`, theme);

			if (details?.truncation?.truncated) {
				text += dim(` (truncated from ${details.truncation.totalLines})`, theme);
			}

			if (expanded) {
				const lang = getLanguageFromPath(path);
				const highlighted = lang ? highlightCode(content.text, lang, theme) : null;
				if (highlighted) {
					text += `\n${highlighted}`;
				} else {
					for (const line of lines.slice(0, 15)) {
						text += `\n${dim(line, theme)}`;
					}
					if (lineCount > 15) {
						text += `\n${dim(`... ${lineCount - 15} more lines`, theme)}`;
					}
				}
			}

			return new Text(text, 0, 0);
		},
	});

	// ── Bash tool ─────────────────────────────────────────────────────────────
	const originalBash = createBashTool(cwd);
	pi.registerTool({
		name: "bash",
		label: "bash",
		description: originalBash.description,
		parameters: originalBash.parameters,
		renderShell: "self",

		async execute(toolCallId, params, signal, onUpdate) {
			return originalBash.execute(toolCallId, params, signal, onUpdate);
		},

		renderCall(args, theme) {
			// Blue accent = pending/in-progress, full command (no truncation)
			let text = theme.fg("accent", `$ ${args.command}`);
			if (args.timeout) text += dim(` (${args.timeout}s)`, theme);
			return new Text(text, 0, 0);
		},

		renderResult(result, { expanded, isPartial }, theme) {
			if (isPartial) return new Text(muted("running…", theme), 0, 0);

			const content = result.content[0];
			const output = content?.type === "text" ? content.text : "";

			const exitMatch = output.match(/exit code: (\d+)/);
			const exitCode = exitMatch ? parseInt(exitMatch[1], 10) : null;
			const lineCount = output.split("\n").filter((l) => l.trim()).length;

			let text = "";
			if (exitCode === 0 || exitCode === null) {
				text += theme.fg("success", "done");
			} else {
				text += theme.fg("error", `exit ${exitCode}`);
			}
			text += dim(` (${lineCount} lines)`, theme);

			const details = result.details as BashToolDetails | undefined;
			if (details?.truncation?.truncated) {
				text += dim(" [truncated]", theme);
			}

			if (expanded) {
				for (const line of output.split("\n").slice(0, 20)) {
					text += `\n${dim(line, theme)}`;
				}
				if (output.split("\n").length > 20) {
					text += `\n${dim("... more output", theme)}`;
				}
			} else if (lineCount > 0) {
				text += dim(" (Ctrl+O to expand)", theme);
			}

			return new Text(text, 0, 0);
		},
	});

	// ── Edit tool ─────────────────────────────────────────────────────────────
	const originalEdit = createEditTool(cwd);
	pi.registerTool({
		name: "edit",
		label: "edit",
		description: originalEdit.description,
		parameters: originalEdit.parameters,
		renderShell: "self",

		async execute(toolCallId, params, signal, onUpdate) {
			return originalEdit.execute(toolCallId, params, signal, onUpdate);
		},

		renderCall(args, theme) {
			return new Text(theme.fg("accent", `edit ${args.path}`), 0, 0);
		},

		renderResult(result, { expanded, isPartial }, theme) {
			if (isPartial) return new Text(muted("editing…", theme), 0, 0);

			const details = result.details as EditToolDetails | undefined;
			const content = result.content[0];

			if (content?.type === "text" && content.text.startsWith("Error")) {
				return new Text(theme.fg("error", content.text.split("\n")[0]), 0, 0);
			}

			if (!details?.diff) {
				return new Text(theme.fg("success", "Applied"), 0, 0);
			}

			const diffLines = details.diff.split("\n");
			let additions = 0, removals = 0;
			for (const line of diffLines) {
				if (line.startsWith("+") && !line.startsWith("+++")) additions++;
				if (line.startsWith("-") && !line.startsWith("---")) removals++;
			}

			// Always show a preview of the diff (first few lines) + stats
			let text = "";
			const previewLines = diffLines.slice(0, 6);
			for (const line of previewLines) {
				if (line.startsWith("+") && !line.startsWith("+++")) {
					text += `\n${theme.fg("success", line)}`;
				} else if (line.startsWith("-") && !line.startsWith("---")) {
					text += `\n${theme.fg("error", line)}`;
				} else if (line.startsWith("@@")) {
					text += `\n${dim(line, theme)}`;
				} else {
					text += `\n${dim(line, theme)}`;
				}
			}

			// Stats at the bottom (like default)
			const remaining = diffLines.length - previewLines.length;
			text += `\n${theme.fg("success", `+${additions} / -${removals}`)}`;
			if (remaining > 0 && !expanded) {
				text += dim(` (${remaining} more lines — Ctrl+O to expand)`, theme);
			}

			// Expanded: show the full diff with same coloring
			if (expanded) {
				const restLines = diffLines.slice(previewLines.length);
				for (const line of restLines) {
					if (line.startsWith("+") && !line.startsWith("+++")) {
						text += `\n${theme.fg("success", line)}`;
					} else if (line.startsWith("-") && !line.startsWith("---")) {
						text += `\n${theme.fg("error", line)}`;
					} else if (line.startsWith("@@")) {
						text += `\n${dim(line, theme)}`;
					} else {
						text += `\n${dim(line, theme)}`;
					}
				}
			}

			return new Text(text, 0, 0);
		},
	});

	// ── Expand toggle command ────────────────────────────────────────────────
	// Ctrl+O is the default pi binding but may conflict in Zellij.
	// /expand provides a command-based alternative.

	pi.registerCommand("expand", {
		description: "Toggle tool output expansion",
		handler: async (_args, ctx) => {
			const expanded = ctx.ui.getToolsExpanded();
			ctx.ui.setToolsExpanded(!expanded);
			ctx.ui.notify(`Tool output ${!expanded ? "expanded" : "collapsed"}`, "info");
		},
	});

	// ── Write tool ────────────────────────────────────────────────────────────
	const originalWrite = createWriteTool(cwd);
	pi.registerTool({
		name: "write",
		label: "write",
		description: originalWrite.description,
		parameters: originalWrite.parameters,
		renderShell: "self",

		async execute(toolCallId, params, signal, onUpdate) {
			return originalWrite.execute(toolCallId, params, signal, onUpdate);
		},

		renderCall(args, theme) {
			const lineCount = args.content.split("\n").length;
			let text = theme.fg("accent", `write ${args.path} (${lineCount} lines)`);
			return new Text(text, 0, 0);
		},

		renderResult(result, { isPartial }, theme) {
			if (isPartial) return new Text(muted("writing…", theme), 0, 0);

			const content = result.content[0];
			if (content?.type === "text" && content.text.startsWith("Error")) {
				return new Text(theme.fg("error", content.text.split("\n")[0]), 0, 0);
			}

			return new Text(theme.fg("success", "Written"), 0, 0);
		},
	});

	// ── Context-mode tool visibility ────────────────────────────────────────
	// Show a brief summary of what ctx_execute/ctx_batch_execute/etc are doing
	let currentCtxTool = "";

	pi.on("tool_execution_start", (event) => {
		if (event.toolName.startsWith("ctx_")) {
			currentCtxTool = `${event.toolName}(${summarizeArgs(event.args)})`;
		}
	});

	pi.on("tool_execution_end", (event) => {
		if (event.toolName.startsWith("ctx_")) {
			currentCtxTool = "";
		}
	});

	// Register a pseudo-status that dashboard-footer can pick up
	// via footerData.getExtensionStatuses() if desired.
	// For now, just make tool_call results more informative.

	function summarizeArgs(args: any): string {
		if (!args) return "";
		if (args.queries) {
			const qs = Array.isArray(args.queries) ? args.queries : [args.queries];
			return qs.map((q: string) => q.slice(0, 40)).join(", ");
		}
		if (args.code) return args.code.slice(0, 60).replace(/\n/g, " ");
		if (args.command) return args.command.slice(0, 80).replace(/\n/g, " ");
		if (args.url) return args.url.slice(0, 60);
		if (args.path) return args.path;
		return JSON.stringify(args).slice(0, 60);
	}
}
