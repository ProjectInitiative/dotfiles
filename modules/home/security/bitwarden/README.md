# security.bitwarden — Bitwarden-backed interactive secrets

Long-running services keep using **sops-nix** (`/run/secrets`). This module
covers the **interactive** surface only. Nothing here ever writes a credential
to a named file on disk, git, or the Nix store.

## Commands

### Auth session shells (bw CLI + jit-auth broker)

```text
k8s-auth        unlock Bitwarden once -> raw kubeconfig held in RAM -> $SHELL
rclone-auth     same for the raw rclone.conf -> RCLONE_CONFIG
```

Inside the session:

- `$PATH` gains a session-local wrapper dir, so plain `kubectl` / `rclone`
  work in scripts, `make`, `python subprocess`, `sh -c`, ... — transparently.
- Each invocation gets a **fresh memfd** (anonymous RAM-only file) handed over
  `SCM_RIGHTS` by `jit-auth-broker`; concurrent commands never share a read
  offset. The config is never written to any named file.
- `BW_SESSION`, `KUBECONFIG_RAW`, `RCLONE_CONFIG_RAW` are never exported into
  the shell. Bitwarden is queried **once per session entry**, not per command.
- Prompt is marked `[$k8s] ...` / `[$rclone] ...`; the reliable hook for your
  own prompt config is the `JIT_AUTH_SESSION` env var.
- `exit` kills the broker, removes the session dir (socket + wrapper), and the
  credential is gone. Traps cover INT/TERM.

### One-shot helpers (rbw, unlock -> grab -> auto-relock)

```text
bw-grab <FIELD> <ITEM> [-- VARNAME]   print value, or emit export line
bw-run <VAR> <ITEM> -- cmd...         secret exists in the child only
rclone-load <BW_ITEM> args...         whole rclone.conf, one command lifetime
argocd-login                          password from the vault
helm-registry-login <REGISTRY>        registry secret from the vault
bw-unlock / bw-lock                   manual vault control
```

## Configuration

```nix
projectinitiative.security.bitwarden = {
  enable = true;
  kubernetes.kubeconfigItem = "<BW item UUID or name>";  # REPLACE-ME
  rclone.configItem = "<BW item UUID or name>";          # REPLACE-ME
};
```

The raw kubeconfig / rclone.conf live in the vault as **secure notes**. To
change extraction (e.g. a custom field), edit `bw_fetch_config()` in
`packages/jit-auth/jit-auth-run`.

## Trust model / security limitations (read this)

This is **session scoping**, not same-UID isolation:

- Anything you deliberately launch **inside** `k8s-auth` may use the session's
  Kubernetes identity. That is the intended feature, not a leak.
- Anything launched **outside** (other terminal, LLM agent, cron) gets
  nothing: no env vars, no PATH wrapper, no reachable socket that survives
  ancestry checks.
- A malicious process already running as the same Unix UID can defeat all of
  this via ptrace / `/proc` / injection. The system defends against:
  persistent credentials on disk, globally exported credentials, accidental
  cross-session reuse, and (via broker ancestry checks + 0600 socket +
  0700 session dir) accidental access from unrelated same-UID processes.

## Testing (fake credentials only)

`packages/jit-auth/test.sh` exercises the broker lifecycle with a fake
kubeconfig: once-per-session retrieval, PATH-wrapper invocation from
bash/sh/scripts, concurrency, env hygiene, and exit cleanup.
