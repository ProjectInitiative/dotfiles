{
  options,
  config,
  pkgs,
  lib,
  namespace,
  osConfig ? { },
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.suites.monitoring;
in
{
  options.${namespace}.suites.monitoring = with types; {
    enable = mkBoolOpt false "Whether or not to enable monitoring suite";
  };

  config = mkIf cfg.enable {
    ${namespace} = {
      services = {
        monitoring = {
          enable = true;

          # Keep the firewall rule creation enabled
          openFirewall = true;

          # Enable the data collectors (exporters) on this machine
          exporters = {
            node = {
              enable = true;
            };
            smartctl = {
              enable = true;
            };
          };

          # Enable Promtail to send logs to a central Loki server
          promtail = {
            enable = true;
            # This should be overridden in the final host configuration
            lokiAddress = "100.119.112.42";
            lokiPort = 3100;

            scrapeConfigs = [
              {
                job_name = "systemd-journal";
                journal = {
                  max_age = "12h";
                  labels = {
                    job = "systemd-journal";
                  };
                };
                relabel_configs = [
                  {
                    source_labels = [ "__journal__systemd_unit" ];
                    target_label = "unit";
                  }
                  {
                    source_labels = [ "__journal__hostname" ];
                    target_label = "host";
                  }
                  {
                    source_labels = [ "__journal__systemd_unit" ];
                    regex = "nvme-debug-collector.service";
                    target_label = "job";
                    replacement = "nvme-debug";
                  }
                ];
              }
            ];
          };

        };
      };

    };

  };
}
