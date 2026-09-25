# security.bitwarden — interactive secrets via Bitwarden (rbw)

Long-running services keep using **sops-nix** (`/run/secrets`). This module
covers the **interactive** surface: secrets are pulled from Bitwarden on demand
and live only in process env vars — no plaintext secret files.

## Model

- `rbw` keeps an encrypted local cache; `pinentry` prompts on demand.
- Every grab runs with `RBW_UNLOCK_TIMEOUT` (default 5s): the vault unlocks,
  serves the secret, and re-locks itself. The master password never lingers.
- `RBW_NONINTERACTIVE=1` option makes any script fail instead of hanging on a
  prompt — useful for wrappers and agents.

## Kubernetes (multiple clusters)

1. Store each cluster's bearer token as a Bitwarden item (field `token`),
   e.g. items `dgx-k8s-token` and `homelab-k8s-token`.
2. Declare clusters in the module and rebuild.
3. Per shell session:

   ```zsh
   eval "$(k8s-token-dgx)"                 # prompts once, exports K8S_TOKEN_DGX
   kubectl --context dgx get pods          # exec-based user reads $K8S_TOKEN_DGX
   kubectl bitwarden unset K8S_TOKEN_DGX   # wipe when done
   ```

   Nothing touches disk: the generated kubeconfig users call `k8s-token-env`,
   which emits the ExecCredential JSON from the env var named by
   `K8S_AUTH_TOKEN_ENV`. The fragment lives in
   `~/.config/kubeauth/kubeconfig` and is merged via `KUBECONFIG`
   (`~/.kube/config:${XDG_CONFIG_HOME}/kubeauth/kubeconfig`) — entries in your
   base kubeconfig win on conflicts.

   Generic versions (work for clusters not declared in the module):

   ```zsh
   eval "$(k8s-token dgx-k8s-token K8S_TOKEN_DGX)"
   bw-run K8S_TOKEN_DGX dgx-k8s-token -- kubectl --context dgx get pods   # one-shot, no export
   kubectl bitwarden token dgx-k8s-token K8S_TOKEN_DGX                    # kubectl plugin spelling
   ```

## rclone

Store the whole `rclone.conf` as a Bitwarden **secure note** (item
`rclone-config` by default), then:

```zsh
rclone-load rclone-config listremotes
rclone-load rclone-config copy bigfile.tar remote:backups/
```

The config is materialized to a 0600 file in `XDG_RUNTIME_DIR` (tmpfs) for
exactly one command, then deleted. `RCLONE_CONFIG` is never persisted.

## Other wrappers

- `bw-grab <FIELD> <ITEM> [-- VARNAME]` — print a field, or emit
  `export VARNAME=...` for `eval "$(bw-grab password x -- X)"`
- `bw-env VARNAME...` — dump only the requested entries from an explicitly
  unlocked vault (`rbw agent env` protocol)
- `bw-run <VAR> <ITEM> -- cmd...` — one-shot; secret exists only in the child
- `argocd-login` — password from the vault, `ARGOCD_SERVER` required
- `helm-registry-login <REGISTRY>` — registry secret from the vault
- `bw-unlock` / `bw-lock` — manual control when you want it

## Session hygiene tips

- Wipe vars when done: `kubectl bitwarden unset K8S_TOKEN_DGX` (they die with
  the shell anyway — zellij panes included).
- Keep `unlockTimeout` small; set `security.bitwarden.nonInteractive = true`
  once your items are named so wrappers never hang on a prompt.
- Enable the rbw agent in your window-manager autostart to avoid repeated
  pinentry prompts: `rbw agent` (or `systemctl --user start rbw-agent`).
