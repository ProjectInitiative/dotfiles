/**
 * Peek Extension — toggle thinking block visibility at runtime
 *
 * This works alongside pi's built-in Ctrl+T (collapse/expand thinking blocks).
 * While hideThinkingBlock controls whether pi renders them at all, this extension
 * lets you toggle it at runtime by updating settings.json and hot-reloading.
 *
 * Commands:
 *   /peek          — Toggle thinking blocks visible/hidden
 *   /peek on       — Show thinking blocks
 *   /peek off      — Hide thinking blocks
 *
 * Shortcuts:
 *   Ctrl+Shift+H   — Toggle peek mode
 *
 * For reference: Ctrl+T (built-in) collapses/expands visible thinking blocks.
 */

import type { ExtensionAPI, AutocompleteItem } from "@earendil-works/pi-coding-agent";
import { readFile, writeFile } from "fs/promises";
import { join, resolve } from "path";

const SETTINGS_PATH = resolve(join(process.env.HOME || "~", ".pi", "agent", "settings.json"));

let peekVisible = false; // true = thinking blocks shown

async function getSettingsDir(): Promise<string> {
  const dir = join(process.env.HOME || "~", ".pi", "agent");
  return resolve(dir);
}

export default function (pi: ExtensionAPI) {
  // ── Register /peek command ────────────────────────────────────────────────
  pi.registerCommand("peek", {
    description: "Toggle thinking block visibility: on, off, or toggle (default)",
    getArgumentCompletions: (prefix: string): AutocompleteItem[] | null => {
      const opts = ["on", "off", "status"];
      const filtered = opts.filter(o => o.startsWith(prefix));
      return filtered.length > 0 ? filtered.map(o => ({ value: o, label: o })) : null;
    },
    handler: async (args, ctx) => {
      const t = ctx.ui.theme;
      const arg = (args || "").trim().toLowerCase();

      if (arg === "status") {
        ctx.ui.notify(
          peekVisible
            ? t.fg("accent", "🧠 Thinking: visible  (Ctrl+T to collapse, Ctrl+Shift+H to hide)")
            : t.fg("dim", "🧠 Thinking: hidden  (Ctrl+Shift+H to peek, Ctrl+T to expand when visible)"),
          "info",
        );
        return;
      }

      if (arg === "on") peekVisible = true;
      else if (arg === "off") peekVisible = false;
      else peekVisible = !peekVisible;

      // Update settings.json to persist the change
      try {
        const settingsPath = await getSettingsDir();
        const raw = await readFile(SETTINGS_PATH, "utf-8");
        const settings = JSON.parse(raw);
        settings.hideThinkingBlock = !peekVisible;
        await writeFile(SETTINGS_PATH, JSON.stringify(settings, null, 2) + "\n");
      } catch {
        // If we can't write settings, just report the state change
      }

      // Persist state across reloads
      pi.appendEntry("peek-state", { peekVisible });

      // Update footer status
      ctx.ui.setStatus("peek", peekVisible ? "🧠 thinking" : undefined);

      ctx.ui.notify(
        peekVisible
          ? t.fg("accent", "🧠 Thinking visible — run /reload or next pi session to apply")
          : t.fg("dim", "🧠 Thinking hidden — run /reload or next pi session to apply"),
        "info",
      );
    },
  });

  // ── Keyboard shortcut ─────────────────────────────────────────────────────
  pi.registerShortcut("ctrl+shift+h", {
    description: "Toggle thinking block visibility",
    handler: async (ctx) => {
      peekVisible = !peekVisible;
      const t = ctx.ui.theme;

      // Update settings.json
      try {
        const raw = await readFile(SETTINGS_PATH, "utf-8");
        const settings = JSON.parse(raw);
        settings.hideThinkingBlock = !peekVisible;
        await writeFile(SETTINGS_PATH, JSON.stringify(settings, null, 2) + "\n");
      } catch { /* ignore */ }

      // Update footer status
      ctx.ui.setStatus("peek", peekVisible ? "🧠 thinking" : undefined);

      ctx.ui.notify(
        peekVisible
          ? t.fg("accent", `🧠 Thinking visible — run /reload to show (or Ctrl+T to expand on next turn)`)
          : t.fg("dim", `🧠 Thinking hidden — run /reload or next session`),
        "info",
      );
    },
  });

  // ── Restore state from session on start ───────────────────────────────────
  pi.on("session_start", async (_event, ctx) => {
    for (const entry of ctx.sessionManager.getEntries()) {
      if (entry.type === "custom" && (entry as any).customType === "peek-state") {
        peekVisible = (entry as any).data?.peekVisible ?? false;
        break;
      }
    }
    ctx.ui.setStatus("peek", peekVisible ? "🧠 thinking" : undefined);
  });
}
