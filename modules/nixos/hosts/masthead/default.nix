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
  cfg = config.${namespace}.hosts.masthead;
in
{
  imports = [
    ./router-config.nix
    ./conntrackd.nix
    ./faucet.nix
    ./keepalived.nix
    ./stormjib.nix
    ./topsail.nix
  ];

  options.${namespace}.hosts.masthead = with types; {
    enable = mkBoolOpt false "Whether or not to enable the masthead HA router base config.";

    routerRole = mkOption {
      type = types.enum [ "primary" "backup" ];
      description = "Role of this router (primary=topsail, backup=stormjib)";
      default = "backup";
    };

    interfaces = {
      wan = mkOption {
        type = types.str;
        description = "WAN data plane interface (SFP+ connected to Brocade 6610)";
        example = "ens1f0";
      };
      lan = mkOption {
        type = types.str;
        description = "LAN interface for internal networks";
        example = "ens2f0";
      };
      sync = mkOption {
        type = types.str;
        description = "Sync/management interface for VRRP heartbeat and conntrackd";
        example = "ens1f1";
      };
    };

    wanSpoofMac = mkOption {
      type = types.str;
      description = "Spoofed MAC address of the original BGW320 for AT&T fiber auth";
      example = "xx:xx:xx:xx:xx:xx";
    };

    openflow = {
      was111Port = mkOption {
        type = types.str;
        default = "1/1/1";
        description = "Brocade 6610 switch port connected to WAS-111 XGS-PON SFP+";
      };
      primaryPort = mkOption {
        type = types.str;
        default = "1/1/2";
        description = "Brocade 6610 switch port connected to topsail SFP+ WAN";
      };
      backupPort = mkOption {
        type = types.str;
        default = "1/1/3";
        description = "Brocade 6610 switch port connected to stormjib SFP+ WAN";
      };
    };

    management = {
      vlanId = mkOption {
        type = types.int;
        default = 1;
        description = "Management VLAN ID (1 = untagged native LAN)";
      };
      network = mkOption {
        type = types.str;
        default = "172.16.1.0/24";
        description = "Management network in CIDR notation";
      };
      primaryIp = mkOption {
        type = types.str;
        default = "172.16.1.2";
        description = "Primary router (topsail) IP on management network";
      };
      backupIp = mkOption {
        type = types.str;
        default = "172.16.1.3";
        description = "Backup router (stormjib) IP on management network";
      };
      virtualIp = mkOption {
        type = types.str;
        default = "172.16.1.1";
        description = "Virtual IP for the active router on management network";
      };
      enableDhcp = mkBoolOpt false "Enable DHCP on the management VLAN (only valid if vlanId == 1)";
      dhcpRangeStart = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      dhcpRangeEnd = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };

    vlans = mkOption {
      type = types.listOf (types.submodule {
        options = {
          id = mkOption { type = types.int; };
          name = mkOption { type = types.str; };
          network = mkOption { type = types.str; };
          virtualIp = mkOption { type = types.str; };
          primaryIp = mkOption { type = types.str; };
          backupIp = mkOption { type = types.str; };
          enableDhcp = mkBoolOpt true;
          dhcpRangeStart = mkOption { type = types.str; };
          dhcpRangeEnd = mkOption { type = types.str; };
          isolated = mkBoolOpt false;
        };
      });
      default = [ ];
    };

    vrrp = {
      enable = mkBoolOpt true "Enable VRRP/keepalived for HA";
      virtualRouterIdBase = mkOption {
        type = types.int;
        default = 50;
        description = "Base VRID for VRRP instances (each VLAN increments from here)";
      };
      priority = {
        primary = mkOption {
          type = types.int;
          default = 150;
        };
        backup = mkOption {
          type = types.int;
          default = 100;
        };
      };
      authPassFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to VRRP authentication password file (e.g., sops secret)";
      };
      keaFailoverPort = mkOption {
        type = types.port;
        default = 647;
        description = "TCP port for Kea DHCP HA failover communication";
      };
    };

    dnsServers = mkOption {
      type = types.listOf types.str;
      default = [ "1.1.1.1" "9.9.9.9" ];
    };

    enableIPv6 = mkBoolOpt true;
  };

  config = mkIf cfg.enable {
    # Disable NetworkManager on router interfaces
    networking.networkmanager.unmanaged = [
      cfg.interfaces.wan
      cfg.interfaces.lan
      cfg.interfaces.sync
    ];

    environment.systemPackages = [ pkgs.conntrack-tools ];
  };
}
