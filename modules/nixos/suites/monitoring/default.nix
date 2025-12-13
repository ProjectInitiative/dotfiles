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
    extraAlloyJournalRelabelRules = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = "Extra relabeling rules to add to the systemd-journal scrape job in Alloy.";
    };
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

          # Enable Alloy to send logs to a central Loki server
          alloy = {
            enable = true;
            # This should be overridden in the final host configuration
            lokiAddress = "100.119.112.42";
            lokiPort = 3100;
            
            journalRelabelConfig = cfg.extraAlloyJournalRelabelRules;
          };

        };
      };

    };

  };
}
