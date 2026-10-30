# Atuin Across Machines

How shell history, AI agent sessions, and terminal output are captured, synced,
and resumed across the ProjectInitiative machines.

## What's enabled (via `suites.terminal-env`)

| Feature | What it does | Syncs across machines? |
| --- | --- | --- |
| Shell history + sync | Encrypted history via `api.atuin.sh` | Yes (encrypted) |
| **Threads** | Captures AI agent sessions (Claude Code, opencode, pi, Codex, Copilot) — conversations, tool calls, file-edit diffs | Yes (encrypted) |
| Daemon | Background process: indexing, scheduled sync, capture | n/a |
| Output capture | Records what terminal commands printed, via the pty-proxy | **No — local disk only** |
| MCP server | Read-only `atuin_history` / `atuin_output` / `atuin_output_search` / `atuin_threads_*` tools for agents | n/a |
| Agent hooks | Agent-run commands land in Atuin history, attributed to the agent | Yes (as history) |

The Atuin package is pinned to nixpkgs master (`upstream` input, 18.24.x) by
`overlays/atuin` because nixpkgs 26.05 ships 18.15.2, which predates
Threads/resume/MCP/output capture.

## The cross-machine workflow

1. Work with Claude Code / opencode / pi on Machine A. The daemon captures the
   session (conversation + tool calls + edit diffs, secrets redacted) into the
   encrypted record store and syncs it automatically every `sync_frequency`
   (10m) — no manual `atuin sync`.
2. On Machine B the session appears after sync. Nothing to configure.
3. Press **Ctrl+]** (or run `atuin resume`) to open the session picker.
4. Pick the session — Atuin reconstructs the transcript from sync if it isn't
   on disk locally, prefers the original agent, and offers forks/continue-in
   options. The agent launches with full context.

```bash
# Browse and resume AI sessions (also Ctrl+])
atuin resume

# Search previous AI conversations
atuin threads search "nixos deployment"

# Search captured terminal output (local only)
atuin output search "build failed"

# Troubleshoot Atuin
atuin doctor
```

Divergence (a session continued on two machines) is handled by Atuin's native
protection: it offers to catch the local copy up, fork from a branch, or
switch — it never silently merges or overwrites. `atuin resume <id> --as-is`,
`--fork`, `--switch`, `--branch`, and `--in <agent>` are available on the CLI.

## Privacy model

- **Command history** is end-to-end encrypted and synced.
- **Threads** (agent sessions) are encrypted and synced. Tool-call
  input/output is captured (`capture_tools = true`) but secrets Atuin
  recognizes are replaced with `****`, `history_filter` / `cwd_filter` /
  `command_filter` matches are kept name-only, and known credential files
  (`.env`, keys, `~/.aws/credentials`, ...) are never captured. Per-call
  data is clipped at 64 KiB. Set `threads.captureTools = false` to record
  tool names only.
- **Captured terminal output is never synced** — it lives in
  `~/.atuin/data/output-capture` on the machine that ran the command, under a
  disk budget (`max_disk_usage`, currently `2GB`). Recognized secrets are
  redacted; output that can't be redacted quickly isn't stored.
- The Atuin **MCP server is read-only** and applies the same filters.

To disable capture on one machine, override in that host's config:

```nix
projectinitiative.cli-apps.atuin.threads.enable = false;        # or
projectinitiative.cli-apps.atuin.outputCapture.enable = false;  # or both
```

## Agent registration (MCP + hooks)

`atuin mcp install <agent>` and `atuin hook install <agent>` run on every
home-manager switch (idempotent, merge-only) for the agents listed in
`suites.terminal-env`: `claude-code`, `opencode`, `pi`. They write the full
nix store path of atuin into each agent's own config file, so the registration
must be refreshed on every switch — do not add these manually.

## One-time / manual operations

- **`atuin login`** — only if a machine was never authenticated. The
  `atuin-login` systemd user service does this automatically on NixOS hosts
  from sops secrets (`autoLogin`); it is disabled on `anchor` and `watchman`.
- **`atuin threads import`** — imports historical agent sessions already on
  disk. Incremental (re-runs only import what's new), but may pull in
  credentials/confidential context from old conversations — run deliberately,
  per machine. Sessions you merely *continue* after enabling capture are
  captured in full automatically; nothing else needs importing.
- **`atuin doctor`** — health check, run if something looks wrong.

## Verification

```bash
atuin --version          # expect 18.24.x
atuin doctor
atuin threads list
atuin daemon status
```

## Rollback

The change is one branch of dotfiles: rebuild the previous generation
(`nh os rollback` or boot the previous system entry). Existing history DB,
encryption key, and auth session under `~/.atuin/` (and legacy
`~/.local/share/atuin/`) are never touched by the config change. Newer Atuin
versions may migrate the local database — Atuin migrations are backwards
compatible, but if you must downgrade a *major* version, restore
`~/.atuin/data` from a backup first.
