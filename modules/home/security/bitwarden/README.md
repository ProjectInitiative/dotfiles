# security.bitwarden — Bitwarden-backed interactive secrets

Long-running services keep using **sops-nix** (`/run/secrets`). This module
covers the **interactive** surface only. Nothing here ever writes a credential
to a named file on disk, git, or the Nix store.

## Commands

### Auth session shells (bw CLI + jit-auth broker)

```text
k8s-auth        unlock Bitwarden once -> broker owns ONE session-lifetime
                mutable memfd -> $SHELL with wrappers for
                kubectl/kubectx/kubens/k9s
rclone-auth     same for the raw rclone.conf -> RCLONE_CONFIG (rclone wrapper)
```

Inside the session:

- `$PATH` gains a session-local wrapper dir, so plain `kubectl`, `kx`, `kn`,
  `k9s`, `rclone` work in scripts, `make`, `python subprocess`, `sh -c`, ... —
  transparently.
- The broker holds the config as **one anonymous, RAM-only memfd for the
  whole session**. Every invocation receives a fresh open-file description of
  that SAME memfd over `SCM_RIGHTS`: independent per-client offsets
  (concurrency-safe) but shared mutable content — so `kx`/`kn` rewrites
  persist across commands and `k9s` sees them. No named file anywhere ever
  contains the config; nothing is discoverable by crawling
  `$XDG_RUNTIME_DIR`.
- `BW_SESSION`, `KUBECONFIG_RAW`, `RCLONE_CONFIG_RAW` and a global
  `KUBECONFIG` are never exported into the shell. Only the wrapped tool
  process itself temporarily receives `KUBECONFIG=/proc/self/fd/N`.
  Bitwarden is queried **once per session entry**, not per command.
- `exit` kills the broker (its memfd — the only copy — closes with it),
  removes the session dir (socket + wrappers), and the credential is gone.
  Traps cover INT/TERM. A new `k8s-auth` starts fresh from the vault.

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
  ancestry checks — and crucially, **no named file to find**: the config is
  an anonymous memfd reachable only through the broker socket.
- A malicious process already running as the same Unix UID can defeat all of
  this via ptrace / `/proc` / injection (it could even talk to the broker if
  it spoofs ancestry — this is a capability boundary, not a wall). The
  system defends against: persistent credentials on disk, globally exported
  credentials, accidental discovery via directory crawling, and accidental
  cross-session reuse.

## Testing (fake credentials only)

`packages/jit-auth/test.sh` exercises the broker lifecycle with a fake
kubeconfig: once-per-session retrieval, PATH-wrapper invocation from
bash/sh/scripts, concurrency, env hygiene, and exit cleanup.
