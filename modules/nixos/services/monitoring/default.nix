# /path/to/your/modules/services/monitoring.nix
{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;

let
  cfg = config.${namespace}.services.monitoring;

  # Submodule definition for a single scrape job
  scrapeJobOpts = {
    options = {
      targets = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "A list of 'host:port' strings for this scrape job.";
        example = [
          "server1.example.com:9100"
          "server2.example.com:9100"
        ];
      };
      extraConfig = mkOption {
        type = types.attrs;
        default = { };
        description = "Any extra prometheus scrape config attributes as a set.";
      };
    };
  };

  # Helper function to generate a list of local targets if exporters are enabled
  localExporterTargets =
    let
      mkTarget = exporter: "${exporter.listenAddress}:${toString exporter.port}";
    in
    (optional cfg.exporters.node.enable (mkTarget cfg.exporters.node))
    ++ (optional cfg.exporters.smartctl.enable (mkTarget cfg.exporters.smartctl));

in
{
  options.${namespace}.services.monitoring = {
    enable = mkEnableOption "Prometheus monitoring and Loki logging services";

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to automatically open firewall ports for enabled services.";
    };

    prometheus = {
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

    loki = {
      enable = mkEnableOption "the Loki logging server";
      listenAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Address for the Loki server to listen on.";
      };
      port = mkOption {
        type = types.port;
        default = 3100;
        description = "Port for the Loki server to listen on.";
      };
      config = mkOption {
        type = types.attrs;
        default = { };
        description = "Extra configuration for Loki's YAML configuration.";
      };
    };

    promtail = {
      enable = mkEnableOption "the Promtail log collector";
      # Removed the 'package' option as it's not a valid attribute
      listenAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Address for Promtail to listen on.";
      };
      port = mkOption {
        type = types.port;
        default = 9080;
        description = "Port for Promtail to listen on.";
      };
      lokiAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "The address of the Loki server to send logs to.";
      };
      lokiPort = mkOption {
        type = types.port;
        default = 3100;
        description = "The port of the Loki server to send logs to.";
      };
      config = mkOption {
        type = types.attrs;
        default = { };
        description = "Extra configuration for Promtail's YAML configuration.";
      };
      scrapeConfigs = mkOption {
        type = types.listOf types.attrs;
        default = [ ];
        description = "A list of scrape jobs for Promtail to collect logs.";
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
      (mkIf cfg.prometheus.enable {
        enable = true;
        inherit (cfg.prometheus)
          package
          listenAddress
          port
          retentionTime
          ;

        scrapeConfigs =
          (mapAttrsToList (
            name: jobCfg:
            jobCfg.extraConfig
            // {
              job_name = name;
              static_configs = [
                {
                  inherit (jobCfg) targets;
                }
              ];
            }
          ) cfg.prometheus.scrapeConfigs)
          # Automatically add a job to scrape this host's own exporters
          ++ (optional (localExporterTargets != [ ]) {
            job_name = "self";
            static_configs = [
              {
                targets = localExporterTargets;
              }
            ];
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

    services.loki = mkIf cfg.loki.enable {
      enable = true;
      configuration = {
        server = {
          http_listen_address = cfg.loki.listenAddress;
          http_listen_port = cfg.loki.port;
        };
      } // cfg.loki.config;
    };

    # Corrected Promtail configuration
    services.promtail = mkIf cfg.promtail.enable {
      enable = true;
      # Removed 'package' from the inherit list
      configuration = {
        server = {
          http_listen_address = cfg.promtail.listenAddress;
          http_listen_port = cfg.promtail.port;
        };
        clients = [
          {
            url = "http://${cfg.promtail.lokiAddress}:${toString cfg.promtail.lokiPort}/loki/api/v1/push";
          }
        ];
        scrape_configs = cfg.promtail.scrapeConfigs;
      } // cfg.promtail.config;
    };

    systemd.services = lib.mkMerge [
      (mkIf cfg.exporters.node.enable {
        "prometheus-node-exporter" = {
          serviceConfig = {
            After = [ "network-online.target" ];
            Requires = [ "network-online.target" ];
            Restart = "on-failure";
            RestartSec = "5s";
          };
        };
      })
      (mkIf cfg.exporters.smartctl.enable {
        "prometheus-smartctl-exporter" = {
          serviceConfig = {
            After = [ "local-fs.target" ];
            Requires = [ "local-fs.target" ];
            Restart = "on-failure";
            RestartSec = "5s";
          };
        };
      })
      # (mkIf cfg.loki.enable {
      #   "loki" = {
      #     serviceConfig = {
      #       After = [ "network-online.target" ];
      #       Requires = [ "network-online.target" ];
      #       Restart = "on-failure";
      #       RestartSec = "5s";
      #     };
      #   };
      # })
      (mkIf cfg.promtail.enable {
        "promtail" = {
          serviceConfig = {
            After = [ "network-online.target" ];
            Requires = [ "network-online.target" ];
            Restart = "on-failure";
            RestartSec = "5s";
          };
        };
      })
    ];

    users.users.prometheus =
      mkIf (cfg.exporters.node.enable || cfg.exporters.smartctl.enable || cfg.prometheus.enable)
        {
          isSystemUser = true;
          group = "prometheus";
          extraGroups = lib.optional cfg.exporters.smartctl.enable "disk";
        };

    users.groups.prometheus = mkIf (
      cfg.exporters.node.enable || cfg.exporters.smartctl.enable || cfg.prometheus.enable
    ) { };

    services.grafana = mkIf cfg.grafana.enable {
      enable = true;
      inherit (cfg.grafana) package dataDir;
      settings = {
        server = {
          http_addr = cfg.grafana.listenAddress;
          http_port = cfg.grafana.port;
        };
      };
      provision.datasources.settings.datasources =
        (optional cfg.prometheus.enable {
          name = "Prometheus (local)";
          type = "prometheus";
          access = "proxy";
          url = "http://${cfg.prometheus.listenAddress}:${toString cfg.prometheus.port}";
          isDefault = true;
        })
        ++ (optional cfg.loki.enable {
          name = "Loki (local)";
          type = "loki";
          access = "proxy";
          url = "http://${cfg.loki.listenAddress}:${toString cfg.loki.port}";
        });
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall (
      (optional cfg.prometheus.enable cfg.prometheus.port)
      ++ (optional cfg.exporters.node.enable cfg.exporters.node.port)
      ++ (optional cfg.exporters.smartctl.enable cfg.exporters.smartctl.port)
      ++ (optional cfg.grafana.enable cfg.grafana.port)
      ++ (optional cfg.loki.enable cfg.loki.port)
      ++ (optional cfg.promtail.enable cfg.promtail.port)
    );
  };
}
