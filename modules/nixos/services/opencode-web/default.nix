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
      example = "/run/secrets/opcode_password";
      description = "Path to a file containing the OpenCode server password.";
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
        DynamicUser = true;
        StateDirectory = "opencode";

        ExecStart = pkgs.writeShellScript "opencode-web-start" ''
          ${optionalString (cfg.passwordFile != null) ''
            export OPENCODE_SERVER_PASSWORD=$(cat ${cfg.passwordFile})
          ''}
          exec ${pkgs.opencode}/bin/opencode web \
            --port ${toString cfg.port} \
            --hostname ${cfg.hostname}
        '';
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
