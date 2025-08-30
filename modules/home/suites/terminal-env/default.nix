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
        git = {
          enable = true;
          userEmail = "6314611+ProjectInitiative@users.noreply.github.com";
          signingKeyFormat = "ssh";
          # TODO: Make this not hardcoded
          signingKey = "/home/kylepzak/.ssh/id_ed25519.pub";
        };
      };
    };
    home = {
      packages = with pkgs; [
        appimage-run
        htop
        btop
        # busybox
        dool
        dogdns
        dust
        fd
        jq
        glow
        mtr
        ncdu
        icdiff
        usbutils
        rclone
        magic-wormhole-rs
        file
        zstd
        xh
        #TODO: add config for yazi
        yazi
        pkgs.${namespace}.flatten-directory
        pkgs.${namespace}.standardize-files
        pkgs.${namespace}.remote-drive-info
        pkgs.${namespace}.health-report
        pkgs.${namespace}.interactive-mv
        pkgs.${namespace}.hdd-burnin        
        pkgs.${namespace}.img-key-injector
        # pkgs.${namespace}.mc
      ];
    };
  };
}
