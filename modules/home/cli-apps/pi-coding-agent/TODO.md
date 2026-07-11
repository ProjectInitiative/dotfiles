# pi-coding-agent module backlog

## Investigate pi.nix integration

**Priority:** Low
**Reference:** https://github.com/lukasl-dev/pi.nix

`pi.nix` provides a Nix wrapper for pi with:

- `programs.pi.coding-agent` NixOS / Home Manager module
- Extension/skill/theme loading via `--extension` CLI flags (store paths)
- Settings.json merging
- Models.json management
- Environment variable injection

**Open questions:**
- Does passing extensions via `--extension` flags conflict with our `~/.pi/agent/extensions/` approach?
- Can we combine both — hot-reloadable extensions on disk + Nix-pinned extensions via CLI?
- Does `pi.nix`'s wrapper approach handle `NPM_CONFIG_PREFIX` for package installs?

## Nixify npm package dependencies

**Priority:** Medium
**Goal:** Fully declarative pi package management (like uv2nix for Python)

### Problem

Pi packages (`pi-subagents`, `pi-web-access`, etc.) are installed at runtime via `pi install npm:@foo/bar`. This:

- Runs `npm install` at runtime
- Downloads dependencies to `~/.pi/agent/npm/`
- Not reproducible without lockfile pinning

### Candidate approaches

| Approach | Description | Pros | Cons |
|----------|-------------|------|------|
| `pkgs.buildNpmPackage` | Build each npm package in Nix | Fully reproducible, store paths | Native addons (better-sqlite3) need compilation |
| `pkgs.fetchNpmDeps` | Newer nixpkgs mechanism | Built into nixpkgs | Still need to handle each package |
| `importNpmLock` | Generate deps from lockfile | Auto-dependency resolution | Requires lockfiles from packages |
| Manual `node2nix` | Generate Nix expressions | Mature tool | Extra generation step, fragile |
| Runtime `pi install` + Nix wrapper | Current approach (`NPM_CONFIG_PREFIX`) | Simple, works now | Not declarative |

### Research needed

- Can we use `pkgs.buildNpmPackage` with `npmInstallHook` for packages that lack native deps?
- Can we bundle pi packages into a single derivation that references pi's bundled modules at runtime?
- Does `@earendil-works/*` scoped packages need special handling (they're bundled with pi)?

## pi_agent_rust — drop-in Rust replacement for Pi

**Priority:** Medium (interesting future option)
**Reference:** https://github.com/Dicklesworthstone/pi_agent_rust

### Status: CERTIFIED drop-in replacement
- 22/22 certification gates PASS, 16/16 blocking gates PASS
- Installer preserves TS pi as `legacy-pi`, Rust pi as `pi`
- <100ms startup, <50MB idle, single ~21MB binary

### Extension system (two runtimes)
| Runtime | What it runs | Dep story |
|---------|-------------|-----------|
| **QuickJS** | Existing JS/TS extensions (ours: permissions, footer, etc.) | Node API shims for fs/path/os/crypto/child_process — no Node/Bun |
| **native-rust** | `.native.json` descriptors | Compiled Rust — zero npm deps |

### Why this could solve our dep problem
Native Rust extensions are compiled descriptors — no npm install, no node_modules,
no better-sqlite3 compilation. If community packages had Rust equivalents,
they'd be single binary deps.

### Research needed
- Do our custom extensions (permissions, footer, tool-renderer, remote-providers)
  work in QuickJS? Need to test Node API shim coverage.
- Are there Rust-native equivalents for installed packages?
  (pi-subagents, pi-web-access, context-mode, pi-mcp-adapter, pi-hypa, crossbar)
- If not, could we rewrite any as native-rust extensions?
  - permissions.ts → built-in security model (capability gates + exec mediation)
  - remote-providers.ts → simpler with native HTTP + JSON parsing
  - dashboard-footer.ts → needs TUI bindings, likely stays JS
- Nix packaging: trivial — single binary, no npm deps

## Remote provider auto-discovery

✅ Solved by `remote-providers.ts` extension — reads providers from `models.json`
and discovers models via `/v1/models` at startup.

## Desired Pi Packages

These npm packages need to be Nixified:

| Package | Version | Purpose | Has native deps? |
|---------|---------|---------|-----------------|
| `pi-subagents` | 0.34.0 | Delegate tasks to subagents with chains/parallel execution | No (jiti only) |
| `pi-web-access` | 0.13.0 | Web search, URL fetch, GitHub clone, PDF/video extraction | No — **but requires pi ≥ 0.79+** (imports `@earendil-works/pi-ai/compat`) |
| `context-mode` | 1.0.169 | MCP context plugin, sandboxed code execution, FTS5 knowledge base | **Yes** (better-sqlite3) |
| `pi-mcp-adapter` | 2.11.0 | MCP protocol adapter for Pi | No |
| `@hypabolic/pi-hypa` | 0.1.10 | Compress noisy tool output out of context window | No |


