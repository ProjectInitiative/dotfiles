{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;

let
  cfg = config.${namespace}.services.opencode-web;
in
{
  options.${namespace}.services.opencode-web = {
    enable = mkEnableOption "OpenCode web interface";

    user = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "kylepzak";
      description = "User to run the service as.";
    };

    port = mkOption {
      type = types.port;
      default = 4096;
      description = "Port for the OpenCode web server to listen on.";
    };

    hostname = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Hostname/IP for the OpenCode web server to bind to.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to automatically open the firewall port for OpenCode web.";
    };

    passwordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/opencode_password";
      description = "Path to a file containing the OpenCode server password. Read by root via LoadCredential.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ opencode ];

    systemd.services.opencode-web = {
      description = "OpenCode Web Interface";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "5s";
        StateDirectory = "opencode";
        User = mkIf (cfg.user != null) cfg.user;
      }
      // optionalAttrs (cfg.passwordFile != null) {
        LoadCredential = "opencode-password:${cfg.passwordFile}";
      };

      script = ''
        ${optionalString (cfg.passwordFile != null) ''
          export OPENCODE_SERVER_PASSWORD=$(cat "$CREDENTIALS_DIRECTORY/opencode-password")
        ''}
        exec ${pkgs.opencode}/bin/opencode web \
          --port ${toString cfg.port} \
          --hostname ${cfg.hostname}
      '';
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
