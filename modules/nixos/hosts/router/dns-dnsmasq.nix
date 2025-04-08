# modules/nixos/hosts/base-router/router/dns-dnsmasq.nix
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
    # Add more dnsmasq specific options if needed, e.g., cache size
    cacheSize = mkOption {
      type = types.int;
      default = 1000;
      description = "DNS cache size for dnsmasq.";
    };
    # cfg.dnsServers is used from the main router config for upstream servers
  };

  config = mkIf (cfg.enable && moduleCfg.enable) {

    services.dnsmasq = {
      enable = true;
      # Listen only on internal interfaces (including virtual IPs for HA)
      extraConfig =
        let
          mgmtInterfaceName =
            if cfg.managementVlan.id == 1 then
              cfg.lanInterface
            else
              "${cfg.lanInterface}.${toString cfg.managementVlan.id}";
          interfaces = [
            mgmtInterfaceName
          ] ++ (map (vlan: "${cfg.lanInterface}.${toString vlan.id}") cfg.vlans);
          # Listen on physical IPs *and* virtual IPs
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
            ++ optional (config.${namespace}.router.vrrp.enable) mgmtVip
            ++ vlanIps
            ++ optional (config.${namespace}.router.vrrp.enable) vlanVips;

        in
        ''
          # Do NOT run DHCP server here
          no-dhcp-interface=*

          # Listen on specific IPs (Physical + Virtual)
          ${concatMapStrings (ip: "listen-address=${ip}\n") listenAddresses}
          # Alternatively, bind only to interfaces:
          # ${concatMapStrings (iface: "interface=${iface}\n") interfaces}
          # bind-interfaces # Use with interface= lines

          # Set DNS cache size
          cache-size=${toString moduleCfg.cacheSize}

          # Add local domain if needed
          # local=/your.internal.domain/
          # domain=your.internal.domain

          # Add custom DNS records if needed
          # address=/my-server.your.internal.domain/192.168.1.50
        '';

      servers = cfg.dnsServers; # Upstream DNS servers
    };

    # Open firewall port for DNS (UDP/TCP 53) on internal interfaces
    networking.firewall = {
      allowedUDPPorts = [ 53 ];
      allowedTCPPorts = [ 53 ];
      # Could restrict to specific interfaces/zones if needed
    };
  };
}
