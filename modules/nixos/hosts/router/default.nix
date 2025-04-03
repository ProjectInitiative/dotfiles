# modules/nixos/hosts/base-router/router/default.nix
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
  cfg = config.${namespace}.router; # Use a shorter path like 'router'
in
{
  imports = [
    ./networking.nix
    ./firewall.nix
    ./dhcp-kea.nix
    ./dns-dnsmasq.nix
    ./vrrp-keepalived.nix
    ./kernel.nix
  ];

  options.${namespace}.router = with types; {
    enable = mkBoolOpt false "Whether or not to enable the router configuration.";

    # --- Options moved here as they affect multiple modules ---
    wanInterface = mkOption {
      type = types.str;
      description = "The network interface connected to the internet/WAN";
      example = "wan0";
      default = "wan0";
    };

    lanInterface = mkOption {
      type = types.str;
      description = "The network interface connected to the internal network/LAN";
      example = "lan0";
      default = "lan0";
    };

    managementVlan = {
      id = mkOption {
        type = types.int;
        description = "Management VLAN ID for router administration";
        default = 1;
      };
      network = mkOption {
        type = types.str;
        description = "Management network in CIDR notation";
        example = "172.16.1.0/24";
        default = "172.16.1.0/24";
      };
      primaryIp = mkOption {
        type = types.str;
        description = "Primary router's IP on management network";
        example = "172.16.1.2";
        default = "172.16.1.2";
      };
      backupIp = mkOption {
        type = types.str;
        description = "Backup router's IP on management network";
        example = "172.16.1.3";
        default = "172.16.1.3";
      };
      virtualIp = mkOption {
        type = types.str;
        description = "Virtual IP for the active router on management network";
        example = "172.16.1.1";
        default = "172.16.1.1";
      };
      enableDhcp = mkOption {
        type = types.bool;
        description = "Whether to enable DHCP on the management VLAN (only if ID is 1 - untagged)";
        default = false; # Usually false for management
      };
      dhcpRangeStart = mkOption {
        type = types.nullOr types.str;
        description = "The start of the DHCP range (for management VLAN, if enabled)";
        example = "172.16.1.100";
        default = null;
      };
      dhcpRangeEnd = mkOption {
        type = types.nullOr types.str;
        description = "The end of the DHCP range (for management VLAN, if enabled)";
        example = "172.16.1.250";
        default = null;
      };
    };

    vlans = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            id = mkOption { type = types.int; description = "VLAN ID"; };
            name = mkOption { type = types.str; description = "VLAN name"; };
            network = mkOption { type = types.str; description = "VLAN network in CIDR notation"; };
            virtualIp = mkOption { type = types.str; description = "Virtual IP (VRRP) for this VLAN"; };
            primaryIp = mkOption { type = types.str; description = "Primary router's IP on this VLAN"; };
            backupIp = mkOption { type = types.str; description = "Backup router's IP on this VLAN"; };
            enableDhcp = mkOption { type = types.bool; default = true; description = "Enable DHCP"; };
            dhcpRangeStart = mkOption { type = types.str; description = "DHCP range start"; };
            dhcpRangeEnd = mkOption { type = types.str; description = "DHCP range end"; };
            isolated = mkOption { type = types.bool; default = false; description = "Isolate from other VLANs"; };
          };
        }
      );
      description = "List of VLANs to configure";
      default = [ ];
    };

    routerRole = mkOption {
      type = types.enum [ "primary" "backup" ];
      description = "Role of this router (primary or backup)";
      default = "primary";
    };

    enableIPv6 = mkOption {
      type = types.bool;
      description = "Whether to enable IPv6 support";
      default = true;
    };

    dnsServers = mkOption {
      type = types.listOf types.str;
      description = "DNS servers to use and provide to DHCP clients";
      default = [ "1.1.1.1" "9.9.9.9" ];
    };
  };

  config = mkIf cfg.enable {
    # Basic system settings needed for a router might go here or in host config
    # system.stateVersion = "23.11"; # Keep in host config

    # Enable IP forwarding (central place)
    boot.kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = true;
      "net.ipv6.conf.all.forwarding" = cfg.enableIPv6;
      # Basic security/sanity settings often needed for routers
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.secure_redirects" = 0;
      "net.ipv4.conf.default.secure_redirects" = 0;
      "net.ipv4.conf.all.send_redirects" = 0; # Routers shouldn't send redirects unless specifically configured
      "net.ipv4.conf.default.send_redirects" = 0;
    };

    networking.enableIPv6 = cfg.enableIPv6;

    # Add base packages needed across modules if not handled per-module
    environment.systemPackages = with pkgs; [
      iproute2 # Essential for advanced networking
      iptables # Needed if using iptables backend for firewall
      tcpdump # Useful for debugging
      ethtool # Useful for interface diagnostics
    ];

    # Recommended: journald settings for a router
    services.journald = {
      rateLimitBurst = 0;
      extraConfig = "SystemMaxUse=50M";
    };

    # Parse networks for convenience (can be used by submodules)
    _module.args.parsedNetworks = let
       parseCIDR = cidr: {
         address = elemAt (builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" cidr) 0;
         prefixLength = toInt (elemAt (builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" cidr) 1);
       };
       mgmtParsed = parseCIDR cfg.managementVlan.network;
       vlansParsed = map (vlan: (parseCIDR vlan.network) // { inherit (vlan) id; }) cfg.vlans;
    in {
       management = mgmtParsed // { id = cfg.managementVlan.id; };
       vlans = vlansParsed;
    };

    assertions =
      [
        {
          assertion = builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" cfg.managementVlan.network != null;
          message = "Management network must be in valid CIDR notation (e.g., 172.16.1.0/24)";
        }
        {
            assertion = cfg.managementVlan.id != 1 -> !(cfg.managementVlan.enableDhcp);
            message = "DHCP can only be enabled on the management VLAN if its ID is 1 (untagged LAN)";
        }
        {
            assertion = !(cfg.managementVlan.enableDhcp) || (cfg.managementVlan.dhcpRangeStart != null && cfg.managementVlan.dhcpRangeEnd != null);
            message = "Management VLAN DHCP requires dhcpRangeStart and dhcpRangeEnd to be set.";
        }
      ]
      ++ (map (vlan: {
        assertion = builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" vlan.network != null;
        message = "VLAN network ${vlan.name} must be in valid CIDR notation";
      }) cfg.vlans)
      ++ (map (vlan: {
        assertion = !(vlan.enableDhcp) || (vlan.dhcpRangeStart != null && vlan.dhcpRangeEnd != null);
        message = "VLAN ${vlan.name} DHCP requires dhcpRangeStart and dhcpRangeEnd to be set.";
      }) (filter (v: v.enableDhcp) cfg.vlans));

  };
}
