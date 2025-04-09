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
        zoxide.enable = true; # Use standard boolean
        zellij.enable = true; # Use standard boolean
        # QOL cli
        bat.enable = true; # Use standard boolean
        eza.enable = true; # Use standard boolean
        ripgrep.enable = true; # Use standard boolean
      };

      tools = {
        alacritty.enable = true; # Use standard boolean
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
        #TODO: add config for yazi
        yazi
        pkgs.flatten-directory # Assuming package name doesn't include namespace
        pkgs.remote-drive-info # Assuming package name doesn't include namespace
        pkgs.health-report # Assuming package name doesn't include namespace
        # pkgs.mc
      ];
    };
  };
}
