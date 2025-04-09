{
  options,
  config,
  lib,
  pkgs,
  # namespace, # No longer needed for helpers
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.cli-apps.atuin;
  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
  isNixOS = options ? environment; # NixOS always has environment config
  isHomeManager = options ? home; # Home Manager always has home config

  loginScript = pkgs.writeShellScript "atuin-login" ''
    #!/usr/bin/env bash
    key=$(${pkgs.coreutils}/bin/cat ${cfg.keyPath} | ${pkgs.coreutils}/bin/tr -d $'\n\r')
    ${pkgs.atuin}/bin/atuin login -u ${cfg.username} -p $(${pkgs.coreutils}/bin/cat ${cfg.passwordPath}) -k "$key"
  '';
in
{
  options.${namespace}.cli-apps.atuin = {
    enable = mkEnableOption "atuin cli."; # Use standard mkEnableOption

    autoLogin = mkOption { # Standard mkOption
      type = types.bool;
      default = false;
      description = "Whether to automatically login to the Atuin server on startup.";
    };

    username = mkOption {
      type = types.str;
      description = "The username for the Atuin server.";
    };

    passwordPath = mkOption {
      type = types.str;
      description = "The path to the sops-nix secret containing the Atuin password.";
    };

    keyPath = mkOption {
      type = types.str;
      description = "The path to the sops-nix secret containing the Atuin encryption key.";
    };
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        atuin
      ];
    };

    # Enable blesh if bash is enabled
    # https://github.com/akinomyoga/ble.sh/wiki/Manual-A1-Installation#user-content-nixpkgs
    # programs.blesh.enable = mkIf config.programs.bash.enable true;

    # Add shell-specific initialization
    programs.zsh.initExtra = mkIf config.programs.zsh.enable ''
      eval "$(atuin init zsh)"
    '';

    programs.bash.initExtra = mkIf config.programs.bash.enable ''
      eval "$(atuin init bash)"
    '';

    programs.fish.shellInit = mkIf config.programs.fish.enable ''
      atuin init fish | source
    '';

    systemd.user.services.atuin-login = mkIf cfg.autoLogin {
      Unit = {
        Description = "Atuin login and initial sync";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };

      Service = {
        Type = "oneshot";
        # Force an initial sync after login
        # ExecStartPost = "${pkgs.atuin}/bin/atuin sync --force";
        ExecStart = "${loginScript}";
        RemainAfterExit = true;
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };

  };

}
