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
  options.${namespace}.hosts.masthead = with types; {
    enable = mkBoolOpt false "Whether or not to enable the masthead router base config.";
  };

  #  config = mkIf cfg.enable {

  #  projectinitiative.hosts.base-router = {
  #    enable = true;

  #    # Interface names
  #    wanInterface = "wan0";
  #    lanInterface = "lan0";

  #    # Management VLAN configuration
  #    managementVlan = {
  #      id = 1;  # Untagged VLAN
  #      network = "172.16.1.0/24";
  #      primaryIp = "172.16.1.2";  # Primary router's IP
  #      backupIp = "172.16.1.3";   # Backup router's IP
  #      virtualIp = "172.16.1.1";  # Virtual IP for management
  #    };

  #    # VRRP base configuration
  #    vrrp = {
  #      enable = true;
  #      routerId = 10;
  #      authPass = "your_vrrp_password_here";  # Use sops-nix in production

  #      # These will be overridden by host-specific configurations
  #      # priority = set in host config
  #      # peerAddress = set in host config
  #    };

  #    # DNS configuration
  #    dnsServers = [
  #      "1.1.1.1"
  #      "9.9.9.9"
  #    ];

  #    # DHCP configuration
  #    # For home network using existing DHCP server:
  #    dhcpMode = "external";
  #    externalDhcpServer = "192.168.1.1";  # Your home router's IP

  #    # For self-hosted DHCP, change to:
  #    # dhcpMode = "internal";

  #    # VLAN definitions shared between all routers
  #    vlans = [
  #      # IoT VLAN
  #      {
  #        id = 21;
  #        name = "iot";
  #        network = "192.168.21.0/24";
  #        virtualIp = "192.168.21.1";  # VRRP address for clients
  #        primaryIp = "192.168.21.2";  # Primary router's IP
  #        backupIp = "192.168.21.3";   # Backup router's IP
  #        enableDhcp = true;
  #        dhcpRangeStart = "192.168.21.100";
  #        dhcpRangeEnd = "192.168.21.250";
  #        isolated = true;  # Isolate IoT devices from other networks
  #      }

  #      # Guest VLAN
  #      {
  #        id = 22;
  #        name = "guest";
  #        network = "192.168.22.0/24";
  #        virtualIp = "192.168.22.1";
  #        primaryIp = "192.168.22.2";
  #        backupIp = "192.168.22.3";
  #        enableDhcp = true;
  #        dhcpRangeStart = "192.168.22.100";
  #        dhcpRangeEnd = "192.168.22.250";
  #        isolated = true;  # Isolate guest network
  #      }

  #      # Home network VLAN
  #      {
  #        id = 10;
  #        name = "home";
  #        network = "192.168.10.0/24";
  #        virtualIp = "192.168.10.1";
  #        primaryIp = "192.168.10.2";
  #        backupIp = "192.168.10.3";
  #        enableDhcp = true;
  #        dhcpRangeStart = "192.168.10.100";
  #        dhcpRangeEnd = "192.168.10.250";
  #        isolated = false;  # Allow communication with other non-isolated VLANs
  #      }

  #      # Media VLAN
  #      {
  #        id = 30;
  #        name = "media";
  #        network = "192.168.30.0/24";
  #        virtualIp = "192.168.30.1";
  #        primaryIp = "192.168.30.2";
  #        backupIp = "192.168.30.3";
  #        enableDhcp = true;
  #        dhcpRangeStart = "192.168.30.100";
  #        dhcpRangeEnd = "192.168.30.250";
  #        isolated = false;
  #      }
  #    ];

  #    # Port forwarding rules (example)
  #    portForwarding = [
  #      {
  #        sourcePort = 80;
  #        destination = "192.168.10.50";
  #        destinationPort = 80;
  #        protocol = "tcp";
  #      }
  #      {
  #        sourcePort = 443;
  #        destination = "192.168.10.50";
  #        destinationPort = 443;
  #        protocol = "tcp";
  #      }
  #    ];
  #  };

  # };
}
