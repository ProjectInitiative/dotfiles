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
  cfg = config.${namespace}.cli-apps.helix;
in
{
  options.${namespace}.cli-apps.helix = with types; {
    enable = mkBoolOpt false "Whether or not to enable common helix editor and language servers.";
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        helix
        # Wayland clipboard bridge — pi (and other TUI apps) shell out to
        # wl-copy/wl-paste for clipboard access; terminal highlight-copy works
        # without it, but in-process copies need the helper.
        wl-clipboard
        # language servers
        lsp-ai
        nil
        nixd
        python313Packages.python-lsp-server
        pyright
      ];

      sessionVariables = {
        EDITOR = "hx";
        VISUAL = "hx";
      };

    };

    # home.sessionVariables is guarded by __HM_SESS_VARS_SOURCED (one-shot per
    # session). When the systemd user manager was started from a login shell,
    # it inherits EDITOR=nano (NixOS set-environment via /etc/zshenv) *plus*
    # the guard already set — so every terminal spawned from the session skips
    # the hx export and sops/git/etc open nano. Re-export unconditionally in
    # interactive shell init so the user-level choice always wins.
    programs.zsh.initContent = mkIf config.programs.zsh.enable ''
      export EDITOR="hx" VISUAL="hx"
    '';

    programs.bash.initExtra = mkIf config.programs.bash.enable ''
      export EDITOR="hx" VISUAL="hx"
    '';

    # GUI-launched apps and user services read environment.d; keeps new
    # services consistent with the interactive shells.
    systemd.user.sessionVariables = {
      EDITOR = "hx";
      VISUAL = "hx";
    };
  };
}
