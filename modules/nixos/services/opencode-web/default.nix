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
      description = "User to run the service as. Enables linger for this user.";
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
      example = "/run/secrets-for-users/user_password";
      description = "Path to a file containing the OpenCode server password. Read by the user service.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ opencode ];

    systemd.user.services.opencode-web = {
      description = "OpenCode Web Interface";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];

      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "5s";
        ExecStart = pkgs.writeShellScript "opencode-web-start" ''
          set -o allexport
          ${optionalString (cfg.passwordFile != null) ''
            export OPENCODE_SERVER_PASSWORD=$(cat ${cfg.passwordFile})
          ''}
          set +o allexport
          exec ${pkgs.opencode}/bin/opencode web \
            --port ${toString cfg.port} \
            --hostname ${cfg.hostname}
        '';
      };
    };

    users.users.${cfg.user}.linger = mkIf (cfg.user != null) true;

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
