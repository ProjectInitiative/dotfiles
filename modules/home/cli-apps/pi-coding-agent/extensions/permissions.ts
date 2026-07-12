/**
 * Full-Spectrum Permission Gate Extension
 *
 * Commands:
 *   /gate              - Show current gate level and status
 *   /gate off          - No gates (pure pi default behavior)
 *   /gate audit        - Log all tool calls, never block
 *   /gate normal       - Confirm dangerous commands, block protected paths (default)
 *   /gate paranoid     - Confirm ALL tool calls
 *   /gate yolo         - Let everything through (same as off, but loud)
 *   /gate yolo <secs>  - Let everything through for N seconds with countdown
 *
 * Protected patterns (normal mode):
 *   - Dangerous bash: rm -rf, sudo, chmod 777, dd, mkfs, fork bomb,
 *                     eval $(curl/wget), curl/wget piped to sh/bash,
 *                     > /dev/sd*, > /dev/nvme*, tee/redirect to /etc/shadow
 *   - Protected paths: .env, .env.*, secrets, credentials, .ssh, .aws,
 *                      .gnupg, /etc/shadow, /etc/sudoers, node_modules/
 *   - Network download-and-execute patterns
 */

import {
  type AutocompleteItem,
  type ExtensionAPI,
  type BashToolInput,
  type WriteToolInput,
  type EditToolInput,
} from "@earendil-works/pi-coding-agent";

// ─── Trust Levels ────────────────────────────────────────────────────────────

type TrustLevel = "off" | "audit" | "normal" | "paranoid" | "yolo";

let currentLevel: TrustLevel = "normal";
let yoloUntil = 0; // epoch ms when yolo timer expires (0 = no timer)
let yoloTimer: ReturnType<typeof setInterval> | null = null;
let toolCallCount = 0;
let blockedCount = 0;
let allowedCount = 0;

// ─── Dangerous Patterns ──────────────────────────────────────────────────────

const DANGEROUS_BASH_PATTERNS: RegExp[] = [
  // Destructive filesystem operations
  /\brm\s+(-rf[^a-zA-Z]|--recursive|--one-file-system)/i,
  /\brm\s+-rf\s+\/\s/i,
  /\bsudo\s+/i,
  /\b(chmod|chown)\b.*777/i,
  /\bdd\s+if=/i,
  /\bmkfs\./i,
  /\bmkswap\b/i,
  /\b parted \b.*(mklabel|mkpart|rm)\b/i,
  /\bfdisk\b.*(delete|wipe)/i,
  // Fork bomb
  /:\s*\(\s*\)\s*\{/i,
  // Network download-and-execute
  /(curl|wget)\s+.*\||\|\s*(bash|sh|zsh)\b/,
  /\beval\s*\(\s*(curl|wget)\b/,
  /\beval\s*"\$\(\s*(curl|wget)\b/,
  // Dangerous redirects
  /[>|]{2,}\s*\/dev\/(sd|nvme|vd|xvd)/,
  /tee\s+-[a]\s+\/etc\/(shadow|sudoers|passwd)/i,
  // Mass file operations
  /\bchmod\s+-R\s+777\b/i,
  /\bchown\s+-R\s+.*:.*\s+\//,
  // Package manager global changes (on non-interactive)
  /(apt|apt-get|dnf|yum|pacman)\s+(remove|purge|autoremove)\s+-/i,
  // Docker destructive
  /\bdocker\s+(system\s+prune|volume\s+rm|network\s+rm)\s+-[af]/i,
  /\bdocker\s+rm\s+-[vf]\b/,
  // Git destructive
  /\bgit\s+push\s+--force\b/i,
  /\bgit\s+reset\s+--hard\b/i,
  /\bgit\s+clean\s+-[fdx]+\b/i,
  // Kill all
  /\bkillall\s+-9\b/i,
  /\bpkill\s+-9\s+-u\s+root\b/i,
  // Shutdown/reboot
  /\bshutdown\s+(-[hHr]|now)\b/,
  /\breboot\b/,
  /\bpoweroff\b/,
  /\binit\s+0\b/,
  // Secrets exposure
  /\becho\s+\$[A-Z_]*SECRET[A-Z_]*\b/i,
  /\bcat\s+\/run\/secrets\//,
  // Write to /etc directly
  /[>|]{1,2}\s*\/etc\/(shadow|sudoers|passwd|ssh|ssl)/i,
];

const PROTECTED_PATH_PATTERNS: RegExp[] = [
  // Secrets and credentials
  /(^|\/)(\.env|\.env\.\w+)$/i,
  /(^|\/)(secrets?|credentials?)\.(json|yaml|yml|toml|env)$/i,
  /(^|\/)\.ssh\//,
  /(^|\/)\.aws\//,
  /(^|\/)\.gnupg\//,
  /(^|\/)\.config\/sops\//,
  // System files
  /^\/etc\/(shadow|sudoers|passwd|gshadow|group-?)$/,
  /^\/boot\//,
  // Dependency directories
  /\/node_modules\//,
  /\/\.git\//,
  // Environment config
  /(^|\/)\.(gitconfig|git-credentials)$/i,
  // Token files
  /(^|\/)(token|\.token|auth\.json|oauth)/i,
];

const PROTECTED_WRITE_TARGETS: RegExp[] = [
  /^\/etc\//,
  /^\/boot\//,
  /^\/dev\//,
  /^\/sys\//,
  /^\/proc\//,
  /^\/run\/secrets\//,
];

// ─── Audit Log ───────────────────────────────────────────────────────────────

interface AuditEntry {
  timestamp: string;
  toolName: string;
  toolCallId: string;
  action: "allowed" | "blocked" | "confirmed" | "denied" | "bypassed" | "logged";
  reason?: string;
  summary: string;
}

const auditLog: AuditEntry[] = [];
const MAX_AUDIT_LOG = 500;

function addAuditEntry(action: AuditEntry["action"], toolName: string, toolCallId: string, summary: string, reason?: string) {
  auditLog.push({
    timestamp: new Date().toISOString(),
    toolName,
    toolCallId,
    action,
    summary: summary.slice(0, 200),
    reason,
  });
  if (auditLog.length > MAX_AUDIT_LOG) auditLog.shift();
}

// ─── Helper: Check if a command matches dangerous patterns ──────────────────

function isDangerousCommand(command: string): { dangerous: boolean; reason?: string } {
  for (const pattern of DANGEROUS_BASH_PATTERNS) {
    if (pattern.test(command)) {
      return { dangerous: true, reason: `Matches dangerous pattern: ${pattern}` };
    }
  }
  return { dangerous: false };
}

function isProtectedPath(path: string): { protected: boolean; reason?: string } {
  for (const pattern of PROTECTED_PATH_PATTERNS) {
    if (pattern.test(path)) {
      return { protected: true, reason: `Matches protected path: ${pattern}` };
    }
  }
  return { protected: false };
}

function isProtectedWriteTarget(path: string): { protected: boolean; reason?: string } {
  for (const pattern of PROTECTED_WRITE_TARGETS) {
    if (pattern.test(path)) {
      return { protected: true, reason: `Protected system path: ${pattern}` };
    }
  }
  return { protected: false };
}

function summarizeBash(command: string): string {
  const lines = command.split("\n").filter(Boolean);
  if (lines.length === 0) return "(empty)";
  const first = lines[0]!.trim();
  if (first.length <= 120) return first;
  return first.slice(0, 117) + "...";
}

function isYoloActive(): boolean {
  return currentLevel === "yolo" || (yoloUntil > 0 && Date.now() < yoloUntil);
}

// ─── The Extension ───────────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  // ── Update status display ──────────────────────────────────────────────────
  function updateStatus(ctx: { ui: { setStatus: (key: string, text: string | undefined) => void; notify: (msg: string, level: string) => void; theme: { fg: (color: string, text: string) => string } } }) {
    const t = ctx.ui.theme;
    if (currentLevel === "off") {
      ctx.ui.setStatus("gate", t.fg("dim", "🔓 off"));
    } else if (currentLevel === "audit") {
      ctx.ui.setStatus("gate", t.fg("muted", "🔍 audit"));
    } else if (currentLevel === "normal") {
      ctx.ui.setStatus("gate", t.fg("success", "🛡 normal"));
    } else if (currentLevel === "paranoid") {
      ctx.ui.setStatus("gate", t.fg("warning", "🔒 paranoid"));
    } else if (isYoloActive()) {
      const remaining = yoloUntil > 0 ? Math.max(0, Math.ceil((yoloUntil - Date.now()) / 1000)) : 0;
      if (remaining > 0) {
        ctx.ui.setStatus("gate", t.fg("error", `🔥 YOLO ${remaining}s`));
      } else {
        ctx.ui.setStatus("gate", t.fg("error", "🔥 YOLO"));
      }
    }
  }

  // ── Cleanup YOLO timer ─────────────────────────────────────────────────────
  function clearYoloTimer() {
    if (yoloTimer) {
      clearInterval(yoloTimer);
      yoloTimer = null;
    }
  }

  // ── Show confirmation dialog ───────────────────────────────────────────────
  async function confirmTool(
    ctx: { ui: { select: (prompt: string, options: string[], opts?: { timeout?: number }) => Promise<string | null>; notify: (msg: string, level: string) => void }; hasUI: boolean },
    title: string,
    message: string,
    toolCallId: string,
    toolName: string,
  ): Promise<boolean> {
    if (!ctx.hasUI) {
      addAuditEntry("blocked", toolName, toolCallId, message, "No UI for confirmation");
      return false;
    }

    const choice = await ctx.ui.select(
      `${title}\n\n${message}\n\nAllow?`,
      ["Allow once", "Allow for 60s", "Deny"],
      { timeout: 30000 },
    );

    if (choice === "Allow for 60s") {
      yoloUntil = Date.now() + 60_000;
      clearYoloTimer();
      yoloTimer = setInterval(() => {
        // Force status refresh on next interaction
      }, 1000);
      ctx.ui.notify("🔥 YOLO mode for 60s", "warning");
      addAuditEntry("bypassed", toolName, toolCallId, message, "User allowed for 60s");
      return true;
    }

    const allowed = choice === "Allow once";
    addAuditEntry(allowed ? "confirmed" : "denied", toolName, toolCallId, message, allowed ? "User allowed" : "User denied");
    return allowed;
  }

  // ── Trust level cycling order ──────────────────────────────────────────────
  const TRUST_LEVELS: TrustLevel[] = ["off", "audit", "normal", "paranoid", "yolo"];

  function cycleTrust(direction: 1 | -1, ctx: { ui: { notify: (msg: string, level: string) => void; setStatus: (key: string, text: string | undefined) => void; theme: { fg: (color: string, text: string) => string } } }) {
    const idx = TRUST_LEVELS.indexOf(currentLevel);
    const next = TRUST_LEVELS[(idx + direction + TRUST_LEVELS.length) % TRUST_LEVELS.length]!;
    currentLevel = next;
    clearYoloTimer();
    yoloUntil = 0;
    ctx.ui.notify(`Gate level: ${formatLevel(next)}`, "info");
    updateStatus(ctx);
  }

  // ── Register /gate command ─────────────────────────────────────────────────
  pi.registerCommand("gate", {
    description: "Set gate level: off, audit, normal, paranoid, yolo, yolo <secs>, status",
    getArgumentCompletions: (prefix: string): AutocompleteItem[] | null => {
      const levels = ["off", "audit", "normal", "paranoid", "yolo"];
      const filtered = levels.filter(l => l.startsWith(prefix));
      return filtered.length > 0
        ? filtered.map(l => ({ value: l, label: l }))
        : null;
    },
    handler: async (args, ctx) => {
      const t = ctx.ui.theme;
      const arg = (args || "").trim().toLowerCase();

      if (!arg || arg === "status") {
        const yoloRemaining = yoloUntil > 0 ? Math.max(0, Math.ceil((yoloUntil - Date.now()) / 1000)) : 0;
        const lines = [
          t.fg("accent", t.bold("Gate Status")),
          "",
          `  Level:    ${formatLevel(currentLevel)}`,
          yoloRemaining > 0 ? `  YOLO:     ${yoloRemaining}s remaining` : "",
          `  Stats:    ${toolCallCount} calls · ${allowedCount} allowed · ${blockedCount} blocked`,
          `  Audit:    ${auditLog.length} entries`,
          "",
          t.fg("dim", "Commands: /gate off | audit | normal | paranoid | yolo | yolo <secs>"),
        ].filter(Boolean).join("\n");
        ctx.ui.notify(lines, "info");
        return;
      }

      const prev = currentLevel;

      if (arg === "off") {
        currentLevel = "off";
        clearYoloTimer();
        yoloUntil = 0;
      } else if (arg === "audit") {
        currentLevel = "audit";
        clearYoloTimer();
        yoloUntil = 0;
      } else if (arg === "normal") {
        currentLevel = "normal";
        clearYoloTimer();
        yoloUntil = 0;
      } else if (arg === "paranoid") {
        currentLevel = "paranoid";
        clearYoloTimer();
        yoloUntil = 0;
      } else if (arg === "yolo" || arg.startsWith("yolo ")) {
        currentLevel = "yolo";
        const parts = arg.split(/\s+/);
        if (parts.length >= 2) {
          const secs = parseInt(parts[1]!);
          if (!isNaN(secs) && secs > 0) {
            yoloUntil = Date.now() + secs * 1000;
            clearYoloTimer();
            yoloTimer = setInterval(() => {
              // Timer-driven status refreshes happen via next tool call
            }, 1000);
            ctx.ui.notify(`🔥 YOLO mode for ${secs}s`, "warning");
          } else {
            yoloUntil = 0;
            ctx.ui.notify("🔥 YOLO mode (unlimited)", "error");
          }
        } else {
          yoloUntil = 0;
          ctx.ui.notify("🔥 YOLO mode (unlimited)", "error");
        }
      } else {
        ctx.ui.notify(`Unknown gate level: ${arg}. Try: off, audit, normal, paranoid, yolo, yolo <secs>`, "error");
        return;
      }

      if (prev !== currentLevel) {
        ctx.ui.notify(`Gate level: ${formatLevel(currentLevel)}${currentLevel === "yolo" ? " 🔥" : ""}`, "info");
      }
      updateStatus(ctx as any);
    },
  });

  // ── Keyboard shortcut: Ctrl+Shift+T to cycle trust levels ─────────────────
  pi.registerShortcut("ctrl+shift+t", {
    description: "Cycle gate level forward",
    handler: async (ctx) => {
      cycleTrust(1, ctx as any);
    },
  });

  // ── Register /audit command to view audit log ──────────────────────────────
  pi.registerCommand("audit", {
    description: "View recent audit log entries",
    handler: async (_args, ctx) => {
      if (auditLog.length === 0) {
        ctx.ui.notify("No audit entries yet.", "info");
        return;
      }

      const t = ctx.ui.theme;
      const lines = [t.fg("accent", t.bold(`Audit Log (last ${auditLog.length} entries)`))];
      const recent = auditLog.slice(-20);
      for (const entry of recent) {
        const icon = entry.action === "blocked" ? "🔴" : entry.action === "denied" ? "⛔" : entry.action === "confirmed" ? "✅" : entry.action === "bypassed" ? "🔥" : entry.action === "allowed" ? "🟢" : "⚪";
        const color = entry.action === "blocked" || entry.action === "denied" ? "error" : entry.action === "bypassed" ? "warning" : "muted";
        lines.push(t.fg(color as any, `  ${icon} ${entry.toolName}: ${entry.summary}`));
        if (entry.reason) {
          lines.push(t.fg("dim", `       → ${entry.reason}`));
        }
      }
      ctx.ui.notify(lines.join("\n"), "info");
    },
  });

  // ── Tool Call Handler ──────────────────────────────────────────────────────
  pi.on("tool_call", async (event, ctx) => {
    toolCallCount++;

    // ── Check YOLO bypass ──────────────────────────────────────────────────
    if (currentLevel === "off" || isYoloActive()) {
      if (currentLevel === "yolo" || yoloUntil > Date.now()) {
        addAuditEntry("bypassed", event.toolName, event.toolCallId, `${event.toolName} call`);
        allowedCount++;
        // Refresh status display
        updateStatus(ctx as any);
      }
      return undefined; // Let everything through
    }

    // ── Audit mode: log but never block ─────────────────────────────────────
    if (currentLevel === "audit") {
      addAuditEntry("logged", event.toolName, event.toolCallId, summarizeCall(event));
      allowedCount++;
      return undefined;
    }

    // ── Paranoid mode: confirm every tool call ──────────────────────────────
    if (currentLevel === "paranoid") {
      const allowed = await confirmTool(
        ctx as any,
        "🔍 Confirm Tool Call",
        `${event.toolName}\n\n${summarizeCall(event)}`,
        event.toolCallId,
        event.toolName,
      );
      if (!allowed) {
        blockedCount++;
        return { block: true, reason: "Blocked by paranoid gate level" };
      }
      allowedCount++;
      return undefined;
    }

    // ── Normal mode: selective enforcement ─────────────────────────────────
    if (currentLevel === "normal") {
      // Bash: check for dangerous commands
      if (event.toolName === "bash") {
        const input = event.input as unknown as BashToolInput;
        const command = input.command || "";
        const { dangerous, reason } = isDangerousCommand(command);

        if (dangerous) {
          const allowed = await confirmTool(
            ctx as any,
            "⚠️ Dangerous Command",
            `$ ${summarizeBash(command)}\n\n${reason}`,
            event.toolCallId,
            event.toolName,
          );
          if (!allowed) {
            blockedCount++;
            return { block: true, reason: `Dangerous command blocked: ${reason}` };
          }
          allowedCount++;
          return undefined;
        }
      }

      // Write: check for protected paths
      if (event.toolName === "write") {
        const input = event.input as unknown as WriteToolInput;
        const path = input.path || "";

        const pathCheck = isProtectedPath(path);
        if (pathCheck.protected) {
          addAuditEntry("blocked", event.toolName, event.toolCallId, `write ${path}`, pathCheck.reason);
          blockedCount++;
          if (ctx.hasUI) {
            const t = (ctx as any).ui.theme;
            (ctx as any).ui.notify(
              t.fg("error", `🔴 Blocked write to protected path: ${path}`),
              "warning",
            );
          }
          return { block: true, reason: `Path "${path}" is protected` };
        }

        const writeTargetCheck = isProtectedWriteTarget(path);
        if (writeTargetCheck.protected) {
          const allowed = await confirmTool(
            ctx as any,
            "⚠️ Writing to System Path",
            `Writing to: ${path}\n\nThis is a protected system path.`,
            event.toolCallId,
            event.toolName,
          );
          if (!allowed) {
            blockedCount++;
            return { block: true, reason: `Write to system path blocked: ${path}` };
          }
          allowedCount++;
          return undefined;
        }
      }

      // Context-mode MCP tools: check for dangerous commands in code
      if (event.toolName === "ctx_execute" || event.toolName === "ctx_batch_execute" || event.toolName === "ctx_execute_file") {
        const code = event.input?.code || event.input?.command || "";
        if (code) {
          const { dangerous, reason } = isDangerousCommand(code);
          if (dangerous) {
            const allowed = await confirmTool(
              ctx as any,
              "⚠️ Dangerous Command in ctx_execute",
              `${event.toolName}\n\n${code.slice(0, 200)}\n\n${reason}`,
              event.toolCallId,
              event.toolName,
            );
            if (!allowed) {
              blockedCount++;
              return { block: true, reason: `Dangerous command blocked in ${event.toolName}: ${reason}` };
            }
            allowedCount++;
            return undefined;
          }
        }
      }

      // Edit: check for protected paths
      if (event.toolName === "edit") {
        const input = event.input as unknown as EditToolInput;
        const path = input.path || "";

        const pathCheck = isProtectedPath(path);
        if (pathCheck.protected) {
          addAuditEntry("blocked", event.toolName, event.toolCallId, `edit ${path}`, pathCheck.reason);
          blockedCount++;
          if (ctx.hasUI) {
            (ctx as any).ui.notify(
              `🔴 Blocked edit to protected path: ${path}`,
              "warning",
            );
          }
          return { block: true, reason: `Path "${path}" is protected` };
        }

        const writeTargetCheck = isProtectedWriteTarget(path);
        if (writeTargetCheck.protected) {
          const allowed = await confirmTool(
            ctx as any,
            "⚠️ Editing System File",
            `Editing: ${path}\n\nThis is a protected system path.`,
            event.toolCallId,
            event.toolName,
          );
          if (!allowed) {
            blockedCount++;
            return { block: true, reason: `Edit to system path blocked: ${path}` };
          }
          allowedCount++;
          return undefined;
        }
      }

      // All other tools: allow in normal mode
      allowedCount++;
      return undefined;
    }

    // Fallback: allow
    allowedCount++;
    return undefined;
  });

  // ── Session start: set initial status ──────────────────────────────────────
  pi.on("session_start", async (_event, ctx) => {
    const t = ctx.ui.theme;
    ctx.ui.setStatus("gate", t.fg("success", "🛡 normal"));
  });

  // ── Update YOLO countdown in status bar on each turn end ──────────────────
  pi.on("turn_end", async (_event, ctx) => {
    if (isYoloActive() || currentLevel === "yolo") {
      updateStatus(ctx as any);
    }
  });
}

// ─── Formatting Helpers ──────────────────────────────────────────────────────

function formatLevel(level: TrustLevel): string {
  switch (level) {
    case "off": return "off (no gates)";
    case "audit": return "audit (log only)";
    case "normal": return "normal (selective)";
    case "paranoid": return "paranoid (confirm all)";
    case "yolo": return "yolo (let it rip)";
  }
}

function summarizeCall(event: { toolName: string; input: any }): string {
  const name = event.toolName;
  const input = event.input;

  switch (name) {
    case "bash": {
      const command = (input as any)?.command || "";
      return `$ ${summarizeBash(command)}`;
    }
    case "write":
    case "edit": {
      const path = (input as any)?.path || "?";
      return `${name} ${path}`;
    }
    case "read": {
      const path = (input as any)?.path || "?";
      return `read ${path}`;
    }
    case "grep": {
      const pattern = (input as any)?.pattern || "?";
      return `grep /${pattern}/`;
    }
    case "find": {
      const pattern = (input as any)?.pattern || "?";
      return `find ${pattern}`;
    }
    case "ls": {
      const path = (input as any)?.path || ".";
      return `ls ${path}`;
    }
    default: {
      return `${name}(${JSON.stringify(input).slice(0, 100)})`;
    }
  }
}
