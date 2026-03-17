{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;
let
  cfg = config.${namespace}.hosts.masthead;
in
{
  config = mkIf cfg.enable {
    systemd.services.multi-wan-healthcheck = {
      description = "Multi-WAN Health Check and Failover Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [
        pkgs.iputils
        pkgs.iproute2
        pkgs.gawk
      ];

      script = ''
        set -euo pipefail

        while true; do
          # Dynamically resolve gateway via wan0
          GATEWAY=$(ip -4 route show default dev wan0 2>/dev/null | awk '{print $3}' | head -n 1 || true)

          if [ -n "$GATEWAY" ]; then
            if ping -I wan0 -c 1 -W 2 "${cfg.healthCheckIp}" > /dev/null 2>&1; then
              # Ping succeeded. Ensure default route exists with appropriate metric
              ip route replace default via "$GATEWAY" dev wan0 metric 10
            else
              # Ping failed. Set metric to 1000 so it acts as disabled but gateway remains discoverable
              ip route replace default via "$GATEWAY" dev wan0 metric 1000 || true
            fi
          fi

          sleep 10
        done
      '';

      serviceConfig = {
        Restart = "always";
        RestartSec = "5s";
      };
    };
  };
}
