{
  options,
  config,
  lib,
  pkgs,
  namespace,
  osConfig ? null,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.suites.terminal-env;
in
{
  options.${namespace}.suites.terminal-env = with types; {
    enable = mkBoolOpt false "Whether or not to enable common terminal-env configuration.";
  };

  config = mkIf cfg.enable {
    ${namespace} = {
      cli-apps = {
        helix = enabled;
        atuin = {
          enable = true;
          autoLogin = mkIf (osConfig != null) true;
          username = mkIf (osConfig != null) "kylepzak";
          passwordPath = mkIf (osConfig != null) osConfig.sops.secrets.kylepzak_atuin_password.path;
          keyPath = mkIf (osConfig != null) osConfig.sops.secrets.kylepzak_atuin_key.path;

        };
        zoxide = enabled;
        zellij = enabled;
        # QOL cli
        bat = enabled;
        eza = enabled;
        ripgrep = enabled;
      };

      tools = {
        alacritty = enabled;
      };
    };
    home = {
      packages = with pkgs; [
        appimage-run
        htop
        btop
        jq
        ncdu
        tree
        icdiff
        usbutils
        rclone
        magic-wormhole
        eternal-terminal
        file
        #TODO: add config for yazi
        yazi
        pkgs.${namespace}.flatten-directory
        pkgs.${namespace}.remote-drive-info
        pkgs.${namespace}.health-report
        pkgs.${namespace}.interactive-mv
        # pkgs.${namespace}.mc
      ];
    };
  };
}
