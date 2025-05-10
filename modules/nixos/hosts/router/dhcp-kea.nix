# modules/nixos/hosts/base-router/router/dhcp-kea.nix
{
  options,
  config,
  lib,
  pkgs,
  namespace,
  modulesPath,
  parsedNetworks, # Passed via _module.args
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.router;
  moduleCfg = config.${namespace}.router.dhcp;

  # Helper to generate subnet config
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
        # Add other DHCP options here if needed
      ];
      # Add reservations here if needed
      # reservations = [ { hw-address = "..."; ip-address = "..."; } ];
    };

in
{
  options.${namespace}.router.dhcp = with types; {
    # Simplified Kea options
    kea = {
      enable = mkBoolOpt false "Whether to enable Kea DHCPv4 server.";

      # Interfaces Kea should listen on (derived automatically)
      # interfaces = mkOption { type = types.listOf types.str; default = []; };

      failover = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              # partnerAddress automatically derived from peerAddress in vrrp config
              # port = mkOption { type = types.port; default = 647; }; # Kea default
              maxUnackedUpdates = mkOption {
                type = types.int;
                default = 10;
              };
              maxAckDelay = mkOption {
                type = types.int;
                default = 1000;
              }; # ms
              mclt = mkOption {
                type = types.int;
                default = 3600;
              }; # seconds
              # hba = mkOption { type = types.int; default = 10; }; # Kea >= 1.6 removed this
              # load-balancing mode options can be added here if needed
            };
          }
        );
        default = null;
        description = "Failover configuration for Kea DHCPv4.";
      };
    };
  };

  # config = mkIf (cfg.enable && moduleCfg.kea.enable) {

  #   # Determine listening interfaces for Kea
  #   _module.args.keaInterfaces = let
  #       mgmtInterfaceName = if cfg.managementVlan.id == 1 then cfg.lanInterface else "${cfg.lanInterface}.${toString cfg.managementVlan.id}";
  #       # Only include management interface if DHCP is enabled for it (only possible if ID=1)
  #       mgmtIf = optional (cfg.managementVlan.id == 1 && cfg.managementVlan.enableDhcp) mgmtInterfaceName;
  #       vlanIfs = map (vlan: "${cfg.lanInterface}.${toString vlan.id}") (filter (v: v.enableDhcp) cfg.vlans);
  #   in mgmtIf ++ vlanIfs;

  #   services.kea-dhcp4 = {
  #     enable = true;
  #     settings = {
  #       Dhcp4 = {
  #         interfaces-config = {
  #           interfaces = config._module.args.keaInterfaces; # Use dynamically generated list
  #           # Specify dhcp-socket-type=raw for performance if needed and supported
  #         };

  #         # Lease database configuration (Memfile is default, consider MySQL/PostgreSQL for HA)
  #         lease-database = {
  #            type = "memfile";
  #            lfc-interval = 3600;
  #         };
  #         # Example PostgreSQL:
  #         # lease-database = {
  #         #   type = "postgresql";
  #         #   name = "kea"; # Database name
  #         #   host = "your_db_host";
  #         #   user = "kea";
  #         #   password = "kea_password";
  #         # };

  #         # Define subnets based on router config
  #         subnet4 = let
  #            # Management subnet (only if ID=1 and DHCP enabled)
  #            mgmtSubnet = optional (cfg.managementVlan.id == 1 && cfg.managementVlan.enableDhcp)
  #              (mkSubnetConfig {
  #                networkInfo = parsedNetworks.management;
  #                vlanCfg = cfg.managementVlan; # Use the managementVlan options directly
  #              });
  #            # VLAN subnets
  #            vlanSubnets = map (vlan:
  #               mkSubnetConfig {
  #                 networkInfo = findFirst (pn: pn.id == vlan.id) null parsedNetworks.vlans;
  #                 vlanCfg = vlan;
  #               }
  #            ) (filter (v: v.enableDhcp) cfg.vlans);
  #         in mgmtSubnet ++ vlanSubnets;

  #         # High Availability / Failover Hookups
  #         "ha-hooks" = mkIf (moduleCfg.kea.failover != null) {
  #            hook-libraries = [
  #               { library = "${pkgs.kea}/lib/kea/hooks/libdhcp_ha.so";
  #                 parameters = {
  #                     high-availability = [
  #                         {
  #                             this-server-name = if cfg.routerRole == "primary" then "kea-router1" else "kea-router2"; # Names must match partner's config
  #                             mode = "load-balancing"; # or "hot-standby"
  #                             heartbeat-delay = 10000; # ms
  #                             max-response-delay = 10000; # ms
  #                             max-ack-delay = moduleCfg.kea.failover.maxAckDelay; # ms
  #                             max-unacked-clients = moduleCfg.kea.failover.maxUnackedUpdates;

  #                             peers = [
  #                                 {
  #                                     name = if cfg.routerRole == "primary" then "kea-router2" else "kea-router1"; # Partner's name
  #                                     # Kea derives partner IP and port from VRRP config if possible, or set explicitly
  #                                     url = "http://${config.${namespace}.router.vrrp.peerAddress}:${toString config.${namespace}.router.vrrp.keaFailoverPort}"; # Use explicit port from VRRP options
  #                                     role = if cfg.routerRole == "primary" then "primary" else "secondary"; # Role in this specific peer relationship
  #                                     # auto-failover = true; # Default
  #                                 }
  #                             ];
  #                         }
  #                     ];
  #                 };
  #               }
  #            ];
  #         };

  #         # Logging (optional, customize as needed)
  #         loggers = [
  #           {
  #             name = "kea-dhcp4";
  #             output_options = [{ output = "stderr"; }]; # or syslog, file
  #             severity = "INFO"; # DEBUG, WARN, ERROR etc.
  #           }
  #         ];
  #       };
  #     };
  #   };

  #   # Required packages
  #   environment.systemPackages = with pkgs; [ kea ];

  #   # Open firewall port for Kea HA communication if failover enabled
  #   networking.firewall = mkIf (moduleCfg.kea.failover != null) {
  #       allowedUDPPorts = [ config.${namespace}.router.vrrp.keaFailoverPort ]; # Allow incoming HA connections
  #       # Or more specific rule using peer address:
  #       # extraCommands = ''
  #       #   iptables -A INPUT -p tcp --dport ${toString config.${namespace}.router.vrrp.keaFailoverPort} -s ${config.${namespace}.router.vrrp.peerAddress} -j ACCEPT
  #       # '';
  #   };

  # };
}
