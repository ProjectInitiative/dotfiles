# Bitwarden-backed interactive secrets.
#
# Design goals:
#   * No plaintext secret files for interactive tooling, ever. Secrets live in
#     the vault and are handed to processes only for the lifetime of an
#     explicitly entered auth session (k8s-auth / rclone-auth via jit-auth).
#   * Long-running services keep using sops-nix (/run/secrets); this module
#     only covers the interactive surface.
#   * rbw + RBW_UNLOCK_TIMEOUT powers the one-shot helpers: unlock -> grab ->
#     auto-relock. jit-auth (bw CLI) powers the session shells.
#
# Session flow:
#   k8s-auth      # unlock once, config held in RAM by jit-auth-broker,
#                 # PATH wrapper for kubectl, exit destroys everything
#   rclone-auth   # same for rclone via RCLONE_CONFIG
#
# One-shot grabs (nothing persists):
#   eval "$(bw-grab password my-item -- MY_VAR)"
#   bw-run MY_VAR my-item -- some-command
#   rclone-load rclone-config listremotes
#
# SECURITY POSTURE: session scoping, not same-UID isolation. A malicious
# process already running as your user can ptrace//proc its way to anything
# this module holds. The point is: no credentials on disk, no globally
# exported credentials, no cross-session reuse. See ./README.md.
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

  # bw-run <ENV_VAR_NAME> <BW_ITEM> -- <command> [args...]
  #   one-shot: secret exported into the child process only, then exec
  runScript = pkgs.writeShellScriptBin "bw-run" ''
    set -euo pipefail
    if [ "$#" -lt 4 ]; then
      echo 'usage: bw-run <ENV_VAR_NAME> <BW_ITEM> -- <command> [args...]' >&2
      exit 64
    fi
    varname="$1"
    item="$2"
    shift 2
    [ "''${1:-}" = "--" ] || { echo 'bw-run: expected -- between <BW_ITEM> and the command' >&2; exit 64; }
    shift
    value=$(${rbw} get "$item")
    export "''${varname}=''${value}"
    exec "$@"
  '';

  # rclone-load <BW_ITEM> [rclone args...]
  #   one-shot: whole rclone.conf from the vault, materialized to a 0600
  #   tmpfs file for exactly one command, then removed.
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

  jitAuth = pkgs.${namespace}.jit-auth.override {
    k8sBitwardenItem = cfg.kubernetes.kubeconfigItem;
    rcloneBitwardenItem = cfg.rclone.configItem;
  };
in
{
  options.${namespace}.security.bitwarden = with types; {
    enable = mkBoolOpt false "Whether or not to enable Bitwarden-backed interactive secrets (rbw one-shots + jit-auth session shells).";

    email = mkOpt types.str "kylepzak" "Bitwarden account email used for `rbw`.";
    serverUrl = mkOpt types.str "https://vault.bitwarden.com" "Bitwarden server URL (change for self-hosted vaultwarden).";
    unlockTimeout = mkOpt types.int 5 "Seconds the vault stays unlocked after an rbw grab; 0 keeps it unlocked (discouraged).";
    noSync = mkOpt types.bool false "Skip vault sync before each rbw grab (faster, stale-tolerant).";
    nonInteractive = mkOpt types.bool false "Never prompt for the master password; fail instead (RBW_NONINTERACTIVE=1).";
    configFile = mkOpt (types.nullOr types.path) null "Custom rbw config file; when null a standard one is generated.";

    rclone = {
      enable = mkOpt types.bool true "Enable rclone helpers (rclone-load one-shot + rclone-auth session shell).";
      configItem = mkOpt types.str "REPLACE-ME" "Bitwarden item (secure note) holding the raw rclone.conf.";
    };

    kubernetes = {
      enable = mkOpt types.bool true "Enable the k8s-auth session shell (raw kubeconfig from Bitwarden).";
      kubeconfigItem = mkOpt types.str "REPLACE-ME" "Bitwarden item (secure note) holding the raw kubeconfig.";
      argoCd = {
        enable = mkOpt types.bool true "Install the argocd-login one-shot helper.";
        item = mkOpt types.str "argocd-password" "Bitwarden item holding the Argo CD password.";
        field = mkOpt types.str "password" "Bitwarden field of the Argo CD item.";
      };
      helmRegistry = {
        enable = mkOpt types.bool true "Install the helm-registry-login one-shot helper.";
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
          pkgs.bitwarden-cli
          jitAuth
          unlockScript
          lockScript
          grabScript
          runScript
        ]
        ++ optionals cfg.rclone.enable [ rcloneLoad ]
        ++ optionals cfg.kubernetes.enable (
          optionals cfg.kubernetes.argoCd.enable [ argocdLogin ]
          ++ optionals cfg.kubernetes.helmRegistry.enable [ helmRegistryLogin ]
        );

      # rbw reads these in every session: the vault re-locks itself after each
      # grab, and sync/prompt behavior is centrally controlled.
      sessionVariables = {
        RBW_UNLOCK_TIMEOUT = toString cfg.unlockTimeout;
      }
      // optionalAttrs cfg.noSync { RBW_NO_SYNC = "1"; }
      // optionalAttrs cfg.nonInteractive { RBW_NONINTERACTIVE = "1"; };
    };

    xdg.configFile = {
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
