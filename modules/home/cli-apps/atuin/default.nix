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
  cfg = config.${namespace}.cli-apps.atuin;
  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
  isNixOS = options ? environment; # NixOS always has environment config
  isHomeManager = options ? home; # Home Manager always has home config

in
{
  options.${namespace}.cli-apps.atuin = with types; {
    enable = mkBoolOpt false "Whether or not to enable atuin cli.";

    autoLogin = mkOption {
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
  };

  systemd.user.services.atuin-login = mkIf cfg.autoLogin {
    Unit = {
      Description = "Atuin login and initial sync";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      Type = "oneshot";
      # Only run if all required login credentials are provided
      ExecStart =
        mkIf (cfg.username != null && cfg.passwordPath != null && cfg.keyPath != null)
          "${pkg.atuin}/bin/atuin login -u ${cfg.username} -p $(cat ${cfg.passwordPath}) -k $(cat ${cfg.keyPath})";
      # Force an initial sync after login
      ExecStartPost = "${pkgs.atuin}/bin/atuin sync --force";
      RemainAfterExit = true;
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

}

# {config, lib, pkgs, ...}:

# let
#   # Get secrets from sops-nix-home
#   username = config.sops.secrets."atuin/username".path or null;
#   password = config.sops.secrets."atuin/password".path or null;
#   key = config.sops.secrets."atuin/key".path or null;

#   # Define conditions based on system type
#   isNixOS = config.isNixOS or false;
#   isLinux = config.isLinux or false;
#   isDarwin = config.isDarwin or false;

#   # Helper to determine if we should create systemd service
#   canUseSystemd = isNixOS || (isLinux && !isNixOS);

#   # Helper to create login script
#   mkLoginScript = name: content:
#     if isDarwin
#     then pkgs.writeScript name content
#     else pkgs.writeShellScript name content;

#   # Common login script content
#   loginScript = ''
#     # Check if all required files exist
#     if [[ -f "${username}" && -f "${password}" && -f "${key}" ]]; then
#       # Read credentials
#       USERNAME=$(cat "${username}")
#       PASSWORD=$(cat "${password}")
#       KEY=$(cat "${key}")

#       # Attempt login
#       ${config.programs.atuin.package}/bin/atuin login \
#         --username "$USERNAME" \
#         --password "$PASSWORD" \
#         --key "$KEY"

#       # Handle service start based on platform
#       if [ $? -eq 0 ]; then
#         ${if canUseSystemd then ''
#           systemctl --user enable atuin
#           systemctl --user start atuin
#         '' else if isDarwin then ''
#           launchctl enable user/atuin
#           launchctl start user/atuin
#         '' else ""}
#       fi
#     else
#       echo "Missing required credentials for Atuin login"
#       exit 0
#     fi
#   '';
# in
# {
#   # Define sops-nix secrets
#   sops.secrets."atuin/username" = {};
#   sops.secrets."atuin/password" = {};
#   sops.secrets."atuin/key" = {};

#   # Conditional systemd service for Linux systems
#   systemd.user.services = lib.mkIf canUseSystemd {
#     atuin-login = {
#       Unit = {
#         Description = "Automatic login for Atuin shell history sync";
#         After = ["network-online.target"];
#         Wants = ["network-online.target"];
#       };

#       Service = {
#         Type = "oneshot";
#         RemainAfterExit = true;
#         ExecStart = let
#           script = if username != null && password != null && key != null
#             then mkLoginScript "atuin-login" loginScript
#             else mkLoginScript "atuin-no-credentials" ''
#               echo 'Atuin credentials not configured'
#               exit 0
#             '';
#         in "${script}";
#       };

#       Install = {
#         WantedBy = ["default.target"];
#       };
#     };
#   };

#   # Launchd service for Darwin systems
#   launchd.agents = lib.mkIf isDarwin {
#     atuin-login = {
#       enable = true;
#       config = {
#         Label = "atuin-login";
#         ProgramArguments = let
#           script = if username != null && password != null && key != null
#             then mkLoginScript "atuin-login" loginScript
#             else mkLoginScript "atuin-no-credentials" ''
#               echo 'Atuin credentials not configured'
#               exit 0
#             '';
#         in [ "${script}" ];
#         RunAtLoad = true;
#         KeepAlive = false;
#         StartInterval = 0;
#         StandardOutPath = "/tmp/atuin-login.log";
#         StandardErrorPath = "/tmp/atuin-login.error.log";
#       };
#     };
#   };

#   # Common atuin configuration
#   programs.atuin = {
#     enable = true;
#     # Add any other atuin configuration you need here
#   };
# }
