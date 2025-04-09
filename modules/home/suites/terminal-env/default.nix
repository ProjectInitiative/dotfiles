{
  options,
  config,
  lib,
  pkgs,
  # namespace, # No longer needed for helpers
  osConfig, # Assume osConfig is passed
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.suites.terminal-env;
in
{
  options.${namespace}.suites.terminal-env = {
    enable = mkEnableOption "common terminal-env configuration."; # Use standard mkEnableOption
  };

  config = mkIf cfg.enable {
    ${namespace} = {
      cli-apps = {
        helix.enable = true; # Use standard boolean
        atuin = {
          enable = true; # Standard boolean
          autoLogin = mkIf (osConfig != null) true; # Standard boolean
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
