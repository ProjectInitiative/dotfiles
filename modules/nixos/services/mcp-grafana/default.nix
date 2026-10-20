# Grafana MCP server (SSE) — gives any MCP agent log (Loki LogQL) and
# dashboard query access through Grafana's RBAC. Runs alongside the local
# Grafana on the monitoring node (dinghy).
#
# Auth model: the server itself has no auth — it proxies with a scoped
# Grafana service-account token (Loki datasource:query only). Expose it on
# trusted networks only (tailnet), same trust level as the mcp-kubernetes
# servers.
{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;

let
  cfg = config.${namespace}.services.mcp-grafana;
in
{
  options.${namespace}.services.mcp-grafana = {
    enable = mkEnableOption "the Grafana MCP server (SSE) for agent access";

    package = mkOption {
      type = types.package;
      default = pkgs.mcp-grafana;
      description = "The mcp-grafana package to use.";
    };

    grafanaUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:3000";
      description = "URL of the Grafana instance to proxy to.";
    };

    port = mkOption {
      type = types.port;
      default = 8000;
      description = "Port for the MCP SSE endpoint.";
    };

    bindAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address for the MCP SSE endpoint to bind.";
    };

    # Rendered by sops-nix (modules/common/encrypted). File content must be
    # a systemd EnvironmentFile with one line:
    #   GRAFANA_SERVICE_ACCOUNT_TOKEN=<token>
    tokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "EnvironmentFile containing GRAFANA_SERVICE_ACCOUNT_TOKEN.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the MCP SSE port in the firewall.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.tokenFile != null;
        message = "${namespace}.services.mcp-grafana.tokenFile is required — the server proxies with a Grafana service-account token.";
      }
    ];

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.mcp-grafana = {
      description = "Grafana MCP server (SSE)";
      after =
        [ "network-online.target" ]
        ++ optional (cfg.tokenFile != null && hasSuffix "/run/secrets-mgmt" (dirOf (toString cfg.tokenFile))) "sops-nix.service";
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment.GRAFANA_URL = cfg.grafanaUrl;

      serviceConfig = {
        ExecStart = ''
          ${cfg.package}/bin/mcp-grafana --transport sse --address ${cfg.bindAddress}:${toString cfg.port}
        '';
        Restart = "on-failure";
        RestartSec = 5;
        DynamicUser = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      } // optionalAttrs (cfg.tokenFile != null) {
        EnvironmentFile = cfg.tokenFile;
      };
    };
  };
}
