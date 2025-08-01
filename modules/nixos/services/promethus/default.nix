# /path/to/your/modules/services/prometheus.nix
{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;

let
  cfg = config.${namespace}.services.prometheus;

  # Submodule definition for a single scrape job
  scrapeJobOpts = {
    options = {
      targets = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "A list of 'host:port' strings for this scrape job.";
        example = [ "server1.example.com:9100" "server2.example.com:9100" ];
      };
      extraConfig = mkOption {
        type = types.attrs;
        default = { };
        description = "Any extra prometheus scrape config attributes as a set.";
      };
    };
  };

  # Helper function to generate a list of local targets if exporters are enabled
  localExporterTargets = let
    mkTarget = exporter: "${exporter.listenAddress}:${toString exporter.port}";
  in
    (optional cfg.exporters.node.enable (mkTarget cfg.exporters.node)) ++
    (optional cfg.exporters.smartctl.enable (mkTarget cfg.exporters.smartctl));


in
{
  options.${namespace}.services.prometheus = {
    enable = mkEnableOption "Prometheus monitoring services";

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to automatically open firewall ports for enabled services.";
    };

    server = {
      enable = mkEnableOption "the Prometheus server";
      package = mkOption {
        type = types.package;
        default = pkgs.prometheus;
        description = "Prometheus package to use.";
      };
      listenAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Address for the Prometheus server to listen on.";
      };
      port = mkOption {
        type = types.port;
        default = 9090;
        description = "Port for the Prometheus server to listen on.";
      };
      retentionTime = mkOption {
        type = types.str;
        default = "30d";
        description = "How long to retain metrics data.";
      };
      scrapeConfigs = mkOption {
        type = types.attrsOf (types.submodule scrapeJobOpts);
        default = { };
        description = "An attribute set of scrape jobs for Prometheus to monitor.";
      };
    };

    grafana = {
        enable = mkEnableOption "the Grafana dashboard server";
        package = mkOption {
            type = types.package;
            default = pkgs.grafana;
            description = "Grafana package to use.";
        };
        listenAddress = mkOption {
            type = types.str;
            default = "0.0.0.0";
            description = "Address for Grafana to listen on.";
        };
        port = mkOption {
            type = types.port;
            default = 3000;
            description = "Port for Grafana to listen on.";
        };
        dataDir = mkOption {
            type = types.path;
            default = "/var/lib/grafana";
            description = "Directory to store Grafana data and dashboards.";
        };
    };

    exporters = {
      node = {
        enable = mkEnableOption "the Node Exporter";
        listenAddress = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = "Address for the Node Exporter to listen on.";
        };
        port = mkOption {
          type = types.port;
          default = 9100;
          description = "Port for the Node Exporter to listen on.";
        };
      };

      smartctl = {
        enable = mkEnableOption "the smartctl Exporter";
        listenAddress = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = "Address for the smartctl Exporter to listen on.";
        };
        port = mkOption {
          type = types.port;
          default = 9633;
          description = "Port for the smartctl Exporter to listen on.";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    
    services.prometheus = lib.mkMerge [
      (mkIf cfg.server.enable {
        enable = true;
        inherit (cfg.server) package listenAddress port retentionTime;

        scrapeConfigs =
          (mapAttrsToList (name: jobCfg: jobCfg.extraConfig // {
            job_name = name;
            static_configs = [{
              inherit (jobCfg) targets;
            }];
          }) cfg.server.scrapeConfigs)
          # Automatically add a job to scrape this host's own exporters
          ++ (optional (localExporterTargets != []) {
               job_name = "self";
               static_configs = [{
                 targets = localExporterTargets;
               }];
             });
      })
      {
        exporters = {
          node = mkIf cfg.exporters.node.enable {
            enable = true;
            inherit (cfg.exporters.node) listenAddress port;
          };
          smartctl = mkIf cfg.exporters.smartctl.enable {
            enable = true;
            inherit (cfg.exporters.smartctl) listenAddress port;
          };
        };
      }
    ];


    # This block correctly defines the prometheus user and group,
    # but only if one of the exporters in this module is enabled.
    # This prevents conflicts and ensures the definition is always complete.
    users.users.prometheus = mkIf (cfg.exporters.node.enable || cfg.exporters.smartctl.enable) {
      isSystemUser = true;
      group = "prometheus";
      # Conditionally add the 'disk' group only when smartctl needs it.
      extraGroups = lib.optional cfg.exporters.smartctl.enable "disk";
    };

    # Also ensure the corresponding group exists.
    users.groups.prometheus = mkIf (cfg.exporters.node.enable || cfg.exporters.smartctl.enable) {};



    services.grafana = mkIf cfg.grafana.enable {
        enable = true;
        inherit (cfg.grafana) package dataDir;
        settings = {
            server = {
                http_addr = cfg.grafana.listenAddress;
                http_port = cfg.grafana.port;
            };
        };
        # If the prometheus server is also enabled on this host, automatically add it as a data source.
        provision.datasources.settings.datasources = optional cfg.server.enable {
            name = "Prometheus (local)";
            type = "prometheus";
            access = "proxy";
            url = "http://${cfg.server.listenAddress}:${toString cfg.server.port}";
            isDefault = true;
        };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall (
      (optional cfg.server.enable cfg.server.port)
      ++ (optional cfg.exporters.node.enable cfg.exporters.node.port)
      ++ (optional cfg.exporters.smartctl.enable cfg.exporters.smartctl.port)
      ++ (optional cfg.grafana.enable cfg.grafana.port)
    );
  };
}
