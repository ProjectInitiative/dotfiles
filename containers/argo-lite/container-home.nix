# Container-local HM policy: which parts of the full kylepzak home config
# activate inside argo-lite. Imported AFTER the full module tree so its
# mkForce/mkDefault settings win.
#
# Enabled (headless dev env): zsh, herdr + mirror plugin, atuin, zellij,
# zoxide, direnv, git, k8s tooling, helix/bat/eza/ripgrep/fd/jq.
#
# Disabled, and why:
# - browsers/messengers/digital-creation/backup suites: GUI or host-machine
#   concepts (browsers, telegram, backup targets) — dead weight in a pod
# - security.sops/bitwarden/gpg: their config paths assume osConfig.sops
#   secrets provisioned by NixOS host activation; no such paths exist in a
#   container. Secrets in the pod come from VSS/openbao instead.
# - atuin autoLogin: needs those same sops secret paths.
{
  lib,
  ...
}:
with lib;
let
  namespace = "projectinitiative";
  # shims for lib.projectinitiative.enabled / .disabled (the namespace
  # lib attr isn't passed into standalone-HM extraSpecialArgs)
  enabled = { enable = true; };
  disabled = { enable = false; };
in
{
  home.stateVersion = "26.05";

  projectinitiative = {
    users.kylepzak.enable = true;

    cli-apps = {
      zsh = enabled;
      herdr = {
        enable = true;
        plugins."nikok6/herdr-mirror" = {
          enable = true;
          repo = "nikok6/herdr-mirror";
        };
      };
      atuin = {
        enable = true;
        autoLogin = mkForce false;
      };
      zellij = enabled;
      zoxide = enabled;
      bat = enabled;
      eza = enabled;
      ripgrep = enabled;
      helix = enabled;
      nix = {
        enable = true;
        # rebuild-host's remote-target workflow makes no sense inside the
        # container itself; keep nh/nom basics only.
      };
      home-manager = enabled;
    };

    tools = {
      direnv = enabled;
      git = {
        enable = true;
        userEmail = "6314611+ProjectInitiative@users.noreply.github.com";
      };
      k8s = enabled;
      ghostty.enable = mkForce false;
      alacritty.enable = mkForce false;
    };

    suites.terminal-env = mkForce enabled;

    # Everything not listed above stays at its default (disabled) — the
    # full module tree is imported but only enable-gated pieces activate.
    suites.ai.enable = mkForce false;
    suites.backup.enable = mkForce false;
    suites.messengers.enable = mkForce false;
    suites.digital-creation.enable = mkForce false;
    # security.* are attrset-options (submodule with .enable), not plain
    # bools — disable via their enable flag.
    security.sops.enable = mkForce false;
    security.gpg.enable = mkForce false;
    security.bitwarden.enable = mkForce false;
  };
}
