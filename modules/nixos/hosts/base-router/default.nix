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
  cfg = config.${namespace}.hosts.base-router;
  # sops = config.sops; # sops config should be handled at the host level importing this module
in
{
  imports = [
    # Import the modular router configuration from the new location
    ./router/default.nix
  ];

  options.${namespace}.hosts.base-router = with types; {
    enable = mkBoolOpt false "Whether or not to enable the masthead router base config.";

    # --- Core Router Options ---
    # These options directly map to the main router module

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
      # DHCP options for management VLAN (only applies if id=1)
      enableDhcp = mkOption {
        type = types.bool;
        description = "Whether to enable DHCP on the management VLAN (only if ID is 1 - untagged)";
        default = false;
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

    # --- Networking Module Options ---
    externalStaticIp = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            address = mkOption { type = types.str; description = "Static external IP address"; };
            prefixLength = mkOption { type = types.int; description = "Prefix length"; };
            gateway = mkOption { type = types.str; description = "Default gateway"; };
          };
        }
      );
      default = null;
      description = "Static external IP configuration (null for DHCP)";
    };

    # --- Firewall Module Options ---
    allowPingFromWan = mkBoolOpt false "Allow ICMP Echo Requests from WAN";

    portForwarding = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            sourcePort = mkOption { type = types.int; };
            destination = mkOption { type = types.str; };
            destinationPort = mkOption { type = types.nullOr types.int; default = null; };
            protocol = mkOption { type = types.enum [ "tcp" "udp" ]; default = "tcp"; };
            description = mkOption { type = types.nullOr types.str; default = null; };
          };
        }
      );
      default = [ ];
      description = "List of port forwarding rules (DNAT)";
    };

    # --- DHCP (Kea) Module Options ---
    keaDhcp4 = {
      enable = mkBoolOpt false "Whether to enable Kea DHCPv4 server.";
      failover = mkOption {
        type = types.nullOr (types.submodule {
          options = {
            maxUnackedUpdates = mkOption { type = types.int; default = 10; };
            maxAckDelay = mkOption { type = types.int; default = 1000; }; # ms
            mclt = mkOption { type = types.int; default = 3600; }; # seconds
          };
        });
        default = null;
        description = "Failover configuration for Kea DHCPv4.";
      };
    };

    # --- DNS (Dnsmasq) Module Options ---
    dnsCacheSize = mkOption {
        type = types.int;
        default = 1000;
        description = "DNS cache size for dnsmasq.";
    };

    # --- VRRP (Keepalived) Module Options ---
    vrrp = {
      enable = mkBoolOpt true "Whether to enable VRRP (Keepalived) for high availability.";
      virtualRouterIdBase = mkOption {
        type = types.int;
        default = 10;
        description = "Base VRRP Virtual Router ID (incremented for each VLAN)";
      };
      priority = mkOption {
        type = types.int;
        default = 100; # Primary typically > 100, Backup < 100
        description = "VRRP priority for this router (higher wins). Set based on routerRole.";
      };
      authPassFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to a file containing the VRRP authentication password.";
        example = ''config.sops.secrets."keepalived_vrrp_password".path''; # Example assumes sops is configured in host
      };
      authPass = mkOption {
         type = types.nullOr types.str;
         default = null;
         description = "VRRP authentication password (plain text, use authPassFile instead).";
      };
      keaFailoverPort = mkOption {
        type = types.port;
        default = 647; # Default Kea HA port
        description = "Port used for Kea DHCP failover communication (if enabled).";
      };
      notifyMasterScript = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Shell command or script path to run when this node becomes MASTER.";
      };
      notifyBackupScript = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Shell command or script path to run when this node becomes BACKUP.";
      };
      notifyFaultScript = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Shell command or script path to run when this node enters FAULT state.";
      };
    };

    # --- Kernel Module Options ---
    extraKernelModules = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional kernel modules to load.";
    };
    extraSysctlSettings = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Additional custom sysctl settings.";
    };

    # --- Deprecated/Removed Options ---
    # dhcpRangeStart, dhcpRangeEnd (moved into managementVlan/vlans)
    # externalDhcpServer, dhcpMode (Kea is the primary DHCP implementation now)
  };

  config = mkIf cfg.enable {
    # Enable the main router module
    ${namespace}.router.enable = true;

    # --- Map base-router options to the main router module ---
    ${namespace}.router = {
      inherit (cfg)
        wanInterface
        lanInterface
        managementVlan
        vlans
        routerRole
        enableIPv6
        dnsServers;

      # Map to networking submodule
      networking.externalStaticIp = cfg.externalStaticIp;

      # Map to firewall submodule
      firewall = {
        inherit (cfg) allowPingFromWan portForwarding;
        enable = true; # Assuming firewall is always enabled if base-router is enabled
      };

      # Map to dhcp-kea submodule
      dhcp.kea = {
        enable = cfg.keaDhcp4.enable;
        failover = cfg.keaDhcp4.failover;
      };

      # Map to dns-dnsmasq submodule
      dns = {
        enable = true; # Assuming DNS is always enabled if base-router is enabled
        cacheSize = cfg.dnsCacheSize;
      };

      # Map to vrrp-keepalived submodule
      vrrp = {
        inherit (cfg.vrrp)
          enable
          virtualRouterIdBase
          priority
          authPassFile
          authPass
          keaFailoverPort
          notifyMasterScript
          notifyBackupScript
          notifyFaultScript;
      };

      # Map to kernel submodule
      kernel = {
        extraModules = cfg.extraKernelModules;
        extraSysctl = cfg.extraSysctlSettings;
      };
    };

    # --- Remove direct configurations previously defined here ---
    # The large commented-out block containing networking, firewall, services, etc.
    # has been removed as these are now handled by the imported modules/router/* files
    # based on the options set above.

  };
}
