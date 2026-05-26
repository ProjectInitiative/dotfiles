{
  options,
  config,
  lib,
  pkgs,
  namespace,
  modulesPath,
  parsedNetworks,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.router;
  moduleCfg = config.${namespace}.router.dhcp;

  mkSubnetConfig =
    { networkInfo, vlanCfg }:
    {
      subnet = networkInfo.address + "/" + toString networkInfo.prefixLength;
      pools = [ { pool = "${vlanCfg.dhcpRangeStart} - ${vlanCfg.dhcpRangeEnd}"; } ];
      option-data = [
        {
          name = "routers";
          data = vlanCfg.virtualIp;
        }
        {
          name = "domain-name-servers";
          data = concatStringsSep "," cfg.dnsServers;
        }
      ];
    } // optionalAttrs (vlanCfg ? reservations && length vlanCfg.reservations > 0) {
      reservations = map (r: {
        hw-address = r.hwAddress;
        ip-address = r.ipAddress;
      }) vlanCfg.reservations;
    };

  peerIp =
    if cfg.routerRole == "primary" then
      cfg.managementVlan.backupIp
    else
      cfg.managementVlan.primaryIp;

  thisServerName =
    if cfg.routerRole == "primary" then "kea-router1" else "kea-router2";
  partnerServerName =
    if cfg.routerRole == "primary" then "kea-router2" else "kea-router1";
in
{
  options.${namespace}.router.dhcp = with types; {
    kea = {
      enable = mkBoolOpt false "Whether to enable Kea DHCPv4 server.";

      failover = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              maxUnackedUpdates = mkOption {
                type = types.int;
                default = 10;
              };
              maxAckDelay = mkOption {
                type = types.int;
                default = 1000;
              };
              mclt = mkOption {
                type = types.int;
                default = 3600;
              };
              failoverPort = mkOption {
                type = types.port;
                default = 647;
                description = "TCP port for Kea DHCP HA failover";
              };
            };
          }
        );
        default = null;
        description = "Failover configuration for Kea DHCPv4.";
      };
    };
  };

  config = mkIf (cfg.enable && moduleCfg.kea.enable) {

    services.kea = {
      dhcp4 = {
        enable = true;
        settings = {
          interfaces-config = {
            interfaces = let
              mgmtInterfaceName = if cfg.managementVlan.id == 1 then cfg.lanInterface else "${cfg.lanInterface}.${toString cfg.managementVlan.id}";
              mgmtIf = optional (cfg.managementVlan.id == 1 && cfg.managementVlan.enableDhcp) mgmtInterfaceName;
              vlanIfs = map (vlan: "${cfg.lanInterface}.${toString vlan.id}") (filter (v: v.enableDhcp) cfg.vlans);
            in mgmtIf ++ vlanIfs;
          };

          lease-database = {
            type = "memfile";
            lfc-interval = 3600;
          };

          subnet4 = let
            mgmtSubnet = optional (cfg.managementVlan.id == 1 && cfg.managementVlan.enableDhcp)
              (mkSubnetConfig {
                networkInfo = parsedNetworks.management;
                vlanCfg = cfg.managementVlan;
              });
            vlanSubnets = map (vlan:
              mkSubnetConfig {
                networkInfo = findFirst (pn: pn.id == vlan.id) null parsedNetworks.vlans;
                vlanCfg = vlan;
              }
            ) (filter (v: v.enableDhcp) cfg.vlans);
          in mgmtSubnet ++ vlanSubnets;

          loggers = [
            {
              name = "kea-dhcp4";
              output_options = [{ output = "stdout"; }];
              severity = "INFO";
            }
          ];
        };
      };
    };

    # Kea DHCP HA hooks (failover)
    services.kea.dhcp4.settings.hooks-libraries = mkIf (moduleCfg.kea.failover != null) [
      {
        library = "${pkgs.kea}/lib/kea/hooks/libdhcp_ha.so";
        parameters = {
          high-availability = [
            {
              this-server-name = thisServerName;
              mode = "hot-standby";
              heartbeat-delay = 10000;
              max-response-delay = 10000;
              max-ack-delay = moduleCfg.kea.failover.maxAckDelay;
              max-unacked-clients = moduleCfg.kea.failover.maxUnackedUpdates;

              peers = [
                {
                  name = partnerServerName;
                  url = "http://${peerIp}:${toString moduleCfg.kea.failover.failoverPort}/";
                  role =
                    if cfg.routerRole == "primary" then "primary" else "secondary";
                }
              ];
            }
          ];
        };
      }
    ];

    environment.systemPackages = with pkgs; [ kea ];

    networking.firewall = mkIf (moduleCfg.kea.failover != null) {
      allowedTCPPorts = [ moduleCfg.kea.failover.failoverPort ];
    };
  };
}
