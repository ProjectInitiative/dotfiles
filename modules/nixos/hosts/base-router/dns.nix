{ config, lib, pkgs, ... }:
let
  cfg = config.${lib.mkModuleName "hosts"}.base-router;
in
{
  services.dnsmasq = {
    enable = true;
    servers = cfg.dnsServers;
    extraConfig = let
      # Basic interface configuration
      baseLan = lib.optionalString (cfg.managementVlan.id == 1) "interface = ${cfg.lanInterface}\n";
      mgmtVlan = lib.optionalString (cfg.managementVlan.id != 1) "interface = ${cfg.lanInterface}.${lib.toString cfg.managementVlan.id}\n";
      otherVlans = lib.concatMapStrings (vlan:
        "interface = ${cfg.lanInterface}.${lib.toString vlan.id}\n"
      ) cfg.vlans;

      # Base configuration
      baseConfig = ''
        bind-interfaces
        ${baseLan}${mgmtVlan}${otherVlans}
      '';

      # DHCP relay configuration (only if external DHCP is enabled)
      relayConfig = lib.optionalString (cfg.dhcpMode == "external" && cfg.externalDhcpServer != null) ''
        # Don't function as a DNS server
        port=0

        # Log lots of extra information about DHCP transactions
        log-dhcp

        # Configure as DHCP relay
        dhcp-relay=${cfg.externalDhcpServer},${cfg.lanInterface}
        ${lib.concatMapStrings (vlan:
          "dhcp-relay=${cfg.externalDhcpServer},${cfg.lanInterface}.${lib.toString vlan.id}\n"
        ) (lib.filter (vlan: vlan.enableDhcp) cfg.vlans)}
      '';
    in
      baseConfig + relayConfig;
  };
};
