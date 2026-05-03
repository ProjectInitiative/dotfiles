{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.masthead;
  activePort =
    if cfg.routerRole == "primary" then
      cfg.openflow.primaryPort
    else
      cfg.openflow.backupPort;

  faucetYaml = pkgs.writeText "faucet.yaml" ''
    dps:
      brocade:
        dp_id: 0x1
        hardware: "Brocade 6610"
        interfaces:
          ${cfg.openflow.was111Port}:
            description: "WAS-111 XGS-PON (AT&T Fiber)"
            output_only: true
            rules:
              - allow: true
                output:
                  - "${activePort}"
          ${cfg.openflow.primaryPort}:
            description: "topsail WAN SFP+"
          ${cfg.openflow.backupPort}:
            description: "stormjib WAN SFP+"
        timeout: 3600
        arp_neighbor_timeout: 3600
  '';

  gaugeYaml = pkgs.writeText "gauge.yaml" ''
    dps:
      brocade:
        interfaces:
          ${cfg.openflow.was111Port}:
            type: port_stats
          ${cfg.openflow.primaryPort}:
            type: port_stats
          ${cfg.openflow.backupPort}:
            type: port_stats
  '';
in
{
  config = mkIf cfg.enable {
    services.faucet = {
      enable = true;
      configFile = faucetYaml;
      listenPort = 6653;
      prometheusPort = 9302;
    };

    services.gauge = {
      enable = true;
      configFile = gaugeYaml;
      listenPort = 6654;
    };

    networking.firewall.allowedTCPPorts = [
      6653
      6654
      9302
    ];
  };
}
