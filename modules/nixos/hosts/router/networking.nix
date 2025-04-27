# modules/nixos/hosts/base-router/router/networking.nix
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
  moduleCfg = config.${namespace}.router.networking;
in
{
  options.${namespace}.router.networking = with types; {
    externalStaticIp = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            address = mkOption {
              type = types.str;
              description = "Static external IP address";
            };
            prefixLength = mkOption {
              type = types.int;
              description = "Prefix length";
            };
            gateway = mkOption {
              type = types.str;
              description = "Default gateway";
            };
          };
        }
      );
      default = null;
      description = "Static external IP configuration (null for DHCP)";
    };

    # Potentially add more networking-specific options here later
  };

  config = mkIf cfg.enable {

    # Define VLAN devices
    networking.vlans = listToAttrs (
      map (vlan: {
        name = "${cfg.lanInterface}.${toString vlan.id}";
        value = {
          id = vlan.id;
          interface = cfg.lanInterface;
        };
      }) cfg.vlans
      # Add management VLAN if it's tagged
      ++ optional (cfg.managementVlan.id != 1) {
        name = "${cfg.lanInterface}.${toString cfg.managementVlan.id}";
        value = {
          id = cfg.managementVlan.id;
          interface = cfg.lanInterface;
        };
      }
    );

    networking.useDHCP = false; # We configure interfaces manually

    # Configure Interfaces (WAN, LAN/Management, VLANs)
    networking.interfaces =
      let
        getIp =
          roleAttrPrefix:
          if cfg.routerRole == "primary" then "${roleAttrPrefix}PrimaryIp" else "${roleAttrPrefix}BackupIp";
        getVlanIp = vlan: if cfg.routerRole == "primary" then vlan.primaryIp else vlan.backupIp;

        mgmtIp =
          if cfg.routerRole == "primary" then cfg.managementVlan.primaryIp else cfg.managementVlan.backupIp;
        mgmtInterfaceName =
          if cfg.managementVlan.id == 1 then
            cfg.lanInterface
          else
            "${cfg.lanInterface}.${toString cfg.managementVlan.id}";

      in
      {
        # WAN Interface
        "${cfg.wanInterface}" = {
          useDHCP = moduleCfg.externalStaticIp == null;
          ipv4 = mkIf (moduleCfg.externalStaticIp != null) {
            addresses = [
              {
                address = moduleCfg.externalStaticIp.address;
                prefixLength = moduleCfg.externalStaticIp.prefixLength;
              }
            ];
          };
          # Basic IPv6 WAN setup (assuming SLAAC/DHCPv6 from ISP)
          ipv6 = mkIf cfg.enableIPv6 {
            addresses = [ ]; # Let RA handle it
            acceptRA = true;
            # useDHCP = true; # If your ISP uses DHCPv6 for addresses
          };
        };

        # Management Interface (Tagged or Untagged)
        "${mgmtInterfaceName}" = {
          ipv4.addresses = [
            {
              address = mgmtIp;
              prefixLength = parsedNetworks.management.prefixLength;
            }
          ];
          ipv6.addresses = [ ]; # Assuming manual or static internal IPv6 later if needed
        };

        # Other VLAN Interfaces
      }
      // listToAttrs (
        map (vlan: {
          name = "${cfg.lanInterface}.${toString vlan.id}";
          value = {
            ipv4.addresses = [
              {
                address = getVlanIp vlan;
                prefixLength = (findFirst (pn: pn.id == vlan.id) null parsedNetworks.vlans).prefixLength;
              }
            ];
            ipv6.addresses = [ ]; # Assuming manual or static internal IPv6 later if needed
          };
        }) cfg.vlans
      );

    # Default Gateway
    networking.defaultGateway = mkIf (moduleCfg.externalStaticIp != null) {
      address = moduleCfg.externalStaticIp.gateway;
      interface = cfg.wanInterface;
    };
    # Note: Default gateway via DHCP is handled automatically if useDHCP=true for WAN

    # NAT Configuration
    networking.nat = {
      enable = true;
      externalInterface = cfg.wanInterface;
      internalInterfaces =
        let
          mgmtInterfaceName =
            if cfg.managementVlan.id == 1 then
              cfg.lanInterface
            else
              "${cfg.lanInterface}.${toString cfg.managementVlan.id}";
        in
        [ mgmtInterfaceName ] ++ (map (vlan: "${cfg.lanInterface}.${toString vlan.id}") cfg.vlans);
      # internalIPs should not be needed if internalInterfaces is correct
    };

    # IPv6 Router Advertisements (basic example, needs customization)
    services.radvd = mkIf cfg.enableIPv6 {
      enable = true;
      config =
        let
          mkPrefix = networkInfo: ''
            prefix ${networkInfo.address}/${toString networkInfo.prefixLength}
            {
                AdvOnLink on;
                AdvAutonomous on;
                AdvRouterAddr on;
            };
          '';
          # This assumes you have manually assigned IPv6 prefixes or derived them somehow
          # Replace with your actual IPv6 prefixes for each VLAN/LAN
          # Example: ULA prefix or delegated prefix from ISP
          # mgmtPrefix6 = "fd00:1::/64";
          # vlanPrefixes6 = { 10 = "fd00:10::/64"; 20 = "fd00:20::/64"; };
          mgmtInterfaceName =
            if cfg.managementVlan.id == 1 then
              cfg.lanInterface
            else
              "${cfg.lanInterface}.${toString cfg.managementVlan.id}";
        in
        ''
          interface ${mgmtInterfaceName} {
              AdvSendAdvert on;
              # ${
                mkPrefix {
                  address = "YOUR_MGMT_IPV6_PREFIX";
                  prefixLength = 64;
                }
              }
              # Route info if needed
              # route ::/0 {};
              # RDNSS info (recursive DNS servers)
              RDNSS ${concatStringsSep " " cfg.dnsServers} {};
          };
        ''
        + concatMapStrings (
          vlan:
          let
            vlanInterfaceName = "${cfg.lanInterface}.${toString vlan.id}";
          in
          ''
            interface ${vlanInterfaceName} {
                AdvSendAdvert on;
                # ${
                  mkPrefix {
                    address = "YOUR_VLAN_${toString vlan.id}_IPV6_PREFIX";
                    prefixLength = 64;
                  }
                }
                # Route info if needed
                # route ::/0 {};
                RDNSS ${concatStringsSep " " cfg.dnsServers} {};
            };
          ''
        ) cfg.vlans;
    };

    # Required packages
    environment.systemPackages = with pkgs; [ vlan ];
  };
}
