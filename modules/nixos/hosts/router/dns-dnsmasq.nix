{
  options,
  config,
  lib,
  pkgs,
  namespace,
  modulesPath,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.router;
  moduleCfg = config.${namespace}.router.dns;
in
{
  options.${namespace}.router.dns = with types; {
    enable = mkBoolOpt true "Whether to enable Dnsmasq as a DNS forwarder/cache.";
    cacheSize = mkOption {
      type = types.int;
      default = 1000;
      description = "DNS cache size for dnsmasq.";
    };
  };

  config = mkIf (cfg.enable && moduleCfg.enable) {

    services.dnsmasq = {
      enable = true;

      settings =
        let
          mgmtInterfaceName =
            if cfg.managementVlan.id == 1 then
              cfg.lanInterface
            else
              "${cfg.lanInterface}.${toString cfg.managementVlan.id}";
          interfaces = [
            mgmtInterfaceName
          ]
          ++ (map (vlan: "${cfg.lanInterface}.${toString vlan.id}") cfg.vlans);

          listenAddresses =
            let
              mgmtIp =
                if cfg.routerRole == "primary" then cfg.managementVlan.primaryIp else cfg.managementVlan.backupIp;
              mgmtVip = cfg.managementVlan.virtualIp;
              vlanIps = map (
                vlan: if cfg.routerRole == "primary" then vlan.primaryIp else vlan.backupIp
              ) cfg.vlans;
              vlanVips = map (vlan: vlan.virtualIp) cfg.vlans;
            in
            [ mgmtIp ]
            ++ optional (config.networking.vrrp.enable) mgmtVip
            ++ vlanIps
            ++ optionals (config.networking.vrrp.enable) vlanVips;
        in
        {
          "listen-address" = listenAddresses;
          "cache-size" = moduleCfg.cacheSize;
          "no-dhcp-interface" = "*";
          "bind-interfaces" = true;
          server = cfg.dnsServers;
        };
    };

    networking.firewall = {
      allowedUDPPorts = [ 53 ];
      allowedTCPPorts = [ 53 ];
    };
  };
}
