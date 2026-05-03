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
in
{
  config = mkIf cfg.enable {
    ${namespace}.router = {
      enable = true;
      routerRole = cfg.routerRole;
      wanInterface = cfg.interfaces.wan;
      lanInterface = cfg.interfaces.lan;
      enableIPv6 = cfg.enableIPv6;
      dnsServers = cfg.dnsServers;

      managementVlan = {
        id = cfg.management.vlanId;
        network = cfg.management.network;
        primaryIp = cfg.management.primaryIp;
        backupIp = cfg.management.backupIp;
        virtualIp = cfg.management.virtualIp;
        enableDhcp = cfg.management.enableDhcp;
        dhcpRangeStart = cfg.management.dhcpRangeStart;
        dhcpRangeEnd = cfg.management.dhcpRangeEnd;
      };

      vlans = cfg.vlans;

      dhcp.kea = {
        enable = true;
        failover = { };
      };
    };

    # WAN MAC Spoofing (BGW320)
    networking.interfaces."${cfg.interfaces.wan}".macAddress = cfg.wanSpoofMac;

    # Sync interface: static IP on management network
    networking.interfaces."${cfg.interfaces.sync}" = {
      useDHCP = false;
      ipv4.addresses = [{
        address = if cfg.routerRole == "primary" then cfg.management.primaryIp else cfg.management.backupIp;
        prefixLength = toInt (builtins.elemAt (builtins.split "/" cfg.management.network) 2);
      }];
    };
  };
}
