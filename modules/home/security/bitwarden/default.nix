# Bitwarden-backed interactive secrets (rbw).
#
# Design goals:
#   * No plaintext secret files for interactive tooling. Secrets live in the
#     Bitwarden vault and are pulled on demand into process-local env vars.
#   * The vault never stays unlocked: every grab runs with RBW_UNLOCK_TIMEOUT
#     so rbw re-locks itself right after serving the secret.
#   * Long-running services keep using sops-nix; this module only covers the
#     interactive surface (kubectl, rclone, argocd, helm, gh, ...).
#
# Session flow (per shell):
#   eval "$(k8s-token-dgx)"          # prompt once, auto-relock, exports K8S_TOKEN_DGX
#   kubectl --context dgx get pods   # exec-based kubeconfig user reads $K8S_TOKEN_DGX
#   kubectl bitwarden unset K8S_TOKEN_DGX
#
# One-shot (nothing exported into the shell):
#   bw-run K8S_TOKEN_DGX dgx-k8s-token -- kubectl --context dgx get pods
#
# See ./README.md for the full wrapper reference.
{
  options,
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.security.bitwarden;

  rbw = "${pkgs.rbw}/bin/rbw";

  clusterSubmodule = types.submodule {
    options = {
      clusterName = mkOpt types.str "" "Kubernetes cluster/context name. Also names the helper script and the kubeconfig user (<name>-token).";
      itemName = mkOpt types.str "" "Bitwarden item holding the cluster bearer token (no spaces).";
      folder = mkOpt (types.nullOr types.str) null "Optional Bitwarden folder to scope the item lookup.";
      field = mkOpt types.str "token" "Bitwarden field of the item that holds the token.";
      envVar = mkOpt types.str "" "Env var the token is exported to. Defaults to K8S_TOKEN_<CLUSTER_NAME> (uppercased, - and . become _).";
    };
  };

  envVarOf =
    c:
    if c.envVar != "" then
      c.envVar
    else
      "K8S_TOKEN_" + strings.toUpper (strings.replaceStrings [ "-" "." ] [ "_" "_" ] c.clusterName);

  validClusters = filter (c: c.clusterName != "" && c.itemName != "") cfg.kubernetes.clusters;

  # Emits the ExecCredential document kubectl expects. Invoked by kubectl via
  # the generated kubeconfig; reads the token from the env var named by
  # K8S_AUTH_TOKEN_ENV so the token itself never touches a file.
  tokenEnvScript = pkgs.writeShellScriptBin "k8s-token-env" ''
    set -euo pipefail
    : "''${K8S_AUTH_TOKEN_ENV:?K8S_AUTH_TOKEN_ENV must name the env var holding the cluster token}"
    token="''${!K8S_AUTH_TOKEN_ENV-}"
    if [ -z "$token" ]; then
      echo "k8s-token-env: \$$K8S_AUTH_TOKEN_ENV is not set." >&2
      echo 'Run the matching k8s-token-<cluster> helper first: eval "$(k8s-token-<cluster>)"' >&2
      exit 1
    fi
    # printf is a bash builtin: no PATH dependency, safe under stripped envs.
    # Escape backslash + double-quote so the token stays valid JSON.
    token_escaped="''${token//\\/\\\\}"
    token_escaped="''${token_escaped//\"/\\\"}"
    printf '{"apiVersion":"client.authentication.k8s.io/v1","kind":"ExecCredential","status":{"token":"%s"}}\n' "$token_escaped"
  '';

  # Generic token exporter: eval "$(k8s-token [--folder F] <item> [VARNAME])"
  tokenScript = pkgs.writeShellScriptBin "k8s-token" ''
    set -euo pipefail
    if [ "$#" -lt 1 ]; then
      echo 'usage: k8s-token [--folder FOLDER] <BW_ITEM> [ENV_VAR_NAME]   (default var: K8S_TOKEN)' >&2
      exit 64
    fi
    folder=""
    if [ "$1" = "--folder" ]; then
      [ "$#" -ge 2 ] || { echo 'k8s-token: --folder needs a value' >&2; exit 64; }
      folder="$2"
      shift 2
    fi
    item="$1"
    varname="''${2:-K8S_TOKEN}"
    if [ -n "$folder" ]; then
      value=$(${rbw} get --field "''${K8S_TOKEN_FIELD:-token}" --folder "$folder" "$item")
    else
      value=$(${rbw} get --field "''${K8S_TOKEN_FIELD:-token}" "$item")
    fi
    printf 'export %s=%q\n' "$varname" "$value"
  '';

  # kubectl plugin form: kubectl bitwarden token <item> [VARNAME]
  kubectlToken = pkgs.writeShellScriptBin "kubectl-token" ''
    set -euo pipefail
    if [ "$#" -lt 1 ]; then
      echo 'usage: kubectl bitwarden token <BW_ITEM> [ENV_VAR_NAME]' >&2
      exit 64
    fi
    item="$1"
    shift
    exec ${tokenScript}/bin/k8s-token "$item" "$@"
  '';

  kubectlUnset = pkgs.writeShellScriptBin "kubectl-unset" ''
    set -euo pipefail
    if [ "$#" -lt 1 ]; then
      echo 'usage: kubectl bitwarden unset <ENV_VAR_NAME>...' >&2
      exit 64
    fi
    for name in "$@"; do
      unset "''${name}" 2>/dev/null || true
      echo "unset $name"
    done
  '';

  unlockScript = pkgs.writeShellScriptBin "bw-unlock" ''
    exec ${rbw} unlock
  '';

  lockScript = pkgs.writeShellScriptBin "bw-lock" ''
    exec ${rbw} lock
  '';

  # bw-grab <FIELD> <ITEM> [-- VARNAME]
  #   prints the value, or an `export VARNAME=...` line for eval
  grabScript = pkgs.writeShellScriptBin "bw-grab" ''
    set -euo pipefail
    if [ "$#" -lt 2 ]; then
      echo 'usage: bw-grab <FIELD> <BW_ITEM> [-- VARNAME]' >&2
      exit 64
    fi
    field="$1"
    item="$2"
    shift 2
    if [ "''${1:-}" = "--" ]; then
      shift
      [ "$#" -eq 1 ] || { echo 'bw-grab: expected one variable name after --' >&2; exit 64; }
      value=$(${rbw} get --field "$field" "$item")
      printf 'export %s=%q\n' "$1" "$value"
    else
      ${rbw} get --field "$field" "$item"
    fi
  '';

  # bw-env <ENV_VAR_NAME>... — dump only these entries from the unlocked vault
  envScript = pkgs.writeShellScriptBin "bw-env" ''
    set -euo pipefail
    [ "$#" -gt 0 ] || { echo 'usage: bw-env <ENV_VAR_NAME>...' >&2; exit 64; }
    argv=()
    for name in "$@"; do
      argv+=(--env "$name")
    done
    exec ${rbw} agent env "''${argv[@]}"
  '';

  # bw-run <ENV_VAR_NAME> <BW_ITEM> -- <command> [args...]
  # Grabs one secret, exports it into the child process only, execs.
  runScript = pkgs.writeShellScriptBin "bw-run" ''
    set -euo pipefail
    if [ "$#" -lt 3 ]; then
      echo 'usage: bw-run <ENV_VAR_NAME> <BW_ITEM> -- <command> [args...]' >&2
      echo 'example: bw-run K8S_TOKEN_DGX dgx-k8s-token -- kubectl --context dgx get pods' >&2
      exit 64
    fi
    varname="$1"
    item="$2"
    shift 2
    [ "$#" -ge 2 ] || { echo 'bw-run: expected -- and a command after <BW_ITEM>' >&2; exit 64; }
    [ "''${1:-}" = "--" ] || { echo 'bw-run: expected -- between <BW_ITEM> and the command' >&2; exit 64; }
    shift
    value=$(${rbw} get "$item")
    export "''${varname}=''${value}"
    exec "$@"
  '';

  # rclone-load <BW_ITEM> [rclone args...]
  # The whole rclone.conf lives in the vault as a secure note; materialized to
  # a 0600 tmpfs-backed file in XDG_RUNTIME_DIR for exactly one command, then
  # removed. RCLONE_CONFIG=<path> rclone ... works as a manual alternative.
  rcloneLoad = pkgs.writeShellScriptBin "rclone-load" ''
    set -euo pipefail
    [ "$#" -ge 1 ] || { echo 'usage: rclone-load <BW_ITEM> [rclone args...]' >&2; exit 64; }
    item="$1"
    shift
    value=$(${rbw} get "$item")
    dir="''${XDG_RUNTIME_DIR:-/tmp}"
    conf=$(mktemp "$dir/rclone.conf.XXXXXX")
    trap 'rm -f "$conf"' EXIT INT TERM
    printf '%s\n' "$value" > "$conf"
    chmod 600 "$conf"
    ${pkgs.rclone}/bin/rclone --config "$conf" "$@"
  '';

  argocdLogin = pkgs.writeShellScriptBin "argocd-login" ''
    set -euo pipefail
    server="''${ARGOCD_SERVER:?set ARGOCD_SERVER, e.g. argocd.example.com}"
    item="''${ARGOCD_BW_ITEM:-${cfg.kubernetes.argoCd.item}}"
    password=$(${rbw} get --field "''${ARGOCD_BW_FIELD:-${cfg.kubernetes.argoCd.field}}" "$item")
    # Note: the password is briefly visible in the process argv; argocd then
    # manages its own credential cache under ~/.config/argocd.
    exec ${pkgs.argocd}/bin/argocd login "$server" --username "''${ARGOCD_USER:-admin}" --password "$password" "$@"
  '';

  helmRegistryLogin = pkgs.writeShellScriptBin "helm-registry-login" ''
    set -euo pipefail
    [ "$#" -ge 1 ] || { echo 'usage: helm-registry-login <REGISTRY> [BW_ITEM]' >&2; exit 64; }
    registry="$1"
    item="''${2:-${cfg.kubernetes.helmRegistry.item}}"
    password=$(${rbw} get --field "''${HELM_BW_FIELD:-${cfg.kubernetes.helmRegistry.field}}" "$item")
    printf '%s' "$password" | ${pkgs.kubernetes-helm}/bin/helm registry login --username "''${HELM_REGISTRY_USER:-${cfg.kubernetes.helmRegistry.username}}" --password-stdin "$registry"
  '';

  # Per-cluster helpers: k8s-token-<cluster> exports K8S_TOKEN_<CLUSTER>.
  clusterScripts = map (
    c:
    pkgs.writeShellScriptBin "k8s-token-${c.clusterName}" ''
      K8S_TOKEN_FIELD=${c.field} exec ${tokenScript}/bin/k8s-token ${optionalString (c.folder != null) "--folder ${c.folder}"} ${c.itemName} ${envVarOf c}
    ''
  ) validClusters;

  # Generated kubeconfig fragment. Merged in via KUBECONFIG chaining; contains
  # only exec-based users, no secrets. Base-file entries win on conflicts, so
  # anything set explicitly in ~/.kube/config still takes precedence.
  generatedKubeconfig = (pkgs.formats.yaml { }).generate "kubeconfig" {
    apiVersion = "v1";
    kind = "Config";
    preferences = { };
    clusters = [ ];
    contexts = [ ];
    users = map (c: {
      name = "${c.clusterName}-token";
      user.exec = {
        apiVersion = "client.authentication.k8s.io/v1";
        interactiveMode = "IfAvailable";
        command = "${tokenEnvScript}/bin/k8s-token-env";
        env = [
          {
            name = "K8S_AUTH_TOKEN_ENV";
            value = envVarOf c;
          }
        ];
      };
    }) validClusters;
  };
in
{
  options.${namespace}.security.bitwarden = with types; {
    enable = mkBoolOpt false "Whether or not to enable Bitwarden-backed interactive secret retrieval (rbw).";

    email = mkOpt types.str "kylepzak" "Bitwarden account email used for `rbw`.";
    serverUrl = mkOpt types.str "https://vault.bitwarden.com" "Bitwarden server URL (change for self-hosted vaultwarden).";
    unlockTimeout = mkOpt types.int 5 "Seconds the vault stays unlocked after a grab; 0 keeps it unlocked for the session (discouraged).";
    noSync = mkOpt types.bool false "Skip vault sync before each grab (faster, stale-tolerant).";
    nonInteractive = mkOpt types.bool false "Never prompt for the master password; fail instead (RBW_NONINTERACTIVE=1).";
    configFile = mkOpt (types.nullOr types.path) null "Custom rbw config file; when null a standard one is generated.";

    rclone = {
      enable = mkOpt types.bool true "Install the rclone-load wrapper (whole rclone.conf stored as a Bitwarden secure note).";
      configItem = mkOpt types.str "rclone-config" "Bitwarden item (secure note) holding the rclone config.";
    };

    kubernetes = {
      enable = mkOpt types.bool true "Install the k8s token helpers and the generated exec-based kubeconfig.";
      clusters = mkOpt (listOf clusterSubmodule) [ ] "Clusters whose bearer tokens live in Bitwarden.";
      argoCd = {
        enable = mkOpt types.bool true "Install the argocd-login helper.";
        item = mkOpt types.str "argocd-password" "Bitwarden item holding the Argo CD password.";
        field = mkOpt types.str "password" "Bitwarden field of the Argo CD item.";
      };
      helmRegistry = {
        enable = mkOpt types.bool true "Install the helm-registry-login helper.";
        item = mkOpt types.str "helm-registry" "Bitwarden item holding the registry secret.";
        field = mkOpt types.str "password" "Bitwarden field of the registry item.";
        username = mkOpt types.str "" "Default registry username (HELM_REGISTRY_USER overrides at runtime).";
      };
    };
  };

  config = mkIf cfg.enable {
    home = {
      packages =
        [
          pkgs.rbw
          pkgs.pinentry-curses
        ]
        ++ [
          unlockScript
          lockScript
          grabScript
          envScript
          runScript
        ]
        ++ optionals cfg.rclone.enable [ rcloneLoad ]
        ++ optionals cfg.kubernetes.enable (
          [
            tokenEnvScript
            tokenScript
            kubectlToken
            kubectlUnset
          ]
          ++ clusterScripts
          ++ optionals cfg.kubernetes.argoCd.enable [ argocdLogin ]
          ++ optionals cfg.kubernetes.helmRegistry.enable [ helmRegistryLogin ]
        );

      # rbw reads these in every session: the vault re-locks itself after each
      # grab, and sync/prompt behavior is centrally controlled.
      sessionVariables = {
        RBW_UNLOCK_TIMEOUT = toString cfg.unlockTimeout;
      }
      // optionalAttrs cfg.noSync { RBW_NO_SYNC = "1"; }
      // optionalAttrs cfg.nonInteractive { RBW_NONINTERACTIVE = "1"; };
      # KUBECONFIG chaining is defined in tools.k8s, gated on this module being
      # enabled, to avoid duplicate-definition conflicts.
    };

    xdg.configFile = {
      # Exec-based kubeconfig users for the declared clusters; merged in via
      # KUBECONFIG chaining. Contains no secrets — only pointers at
      # k8s-token-env plus the env var names to read.
      "kubeauth/kubeconfig" = mkIf cfg.kubernetes.enable {
        source = generatedKubeconfig;
      };

      "rbw/config.json" = mkIf (cfg.configFile == null) {
        text =
          builtins.toJSON {
            email = cfg.email;
            baseserver = cfg.serverUrl;
            pinentry = "pinentry-curses";
            unlock_timeout = cfg.unlockTimeout;
        };
      };
    };
  };
}
