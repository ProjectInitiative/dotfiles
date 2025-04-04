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

<<<<<<< Updated upstream
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
=======
  # --- Router Configuration (using base-router module) ---
  # ${namespace}.router = {
  #   enable = true;
  #   routerRole = routerRole; # Pass role defined above

  #   # --- Interfaces ---
  #   wanInterface = "eth0"; # Adjust to your hardware
  #   lanInterface = "eth1"; # Adjust to your hardware

  #   # --- Management Network ---
  #   managementVlan = {
  #     id = 10; # Tagged management VLAN
  #     network = "172.16.10.0/24";
  #     primaryIp = "172.16.10.2";
  #     backupIp = "172.16.10.3";
  #     virtualIp = "172.16.10.1";
  #     # enableDhcp = false; # Default is false
  #   };

  #   # --- User VLANs ---
  #   vlans = [
  #     {
  #       id = 20;
  #       name = "users";
  #       network = "192.168.20.0/24";
  #       primaryIp = "192.168.20.2";
  #       backupIp = "192.168.20.3";
  #       virtualIp = "192.168.20.1";
  #       enableDhcp = true;
  #       dhcpRangeStart = "192.168.20.100";
  #       dhcpRangeEnd = "192.168.20.200";
  #     }
  #     {
  #       id = 30;
  #       name = "iot";
  #       network = "192.168.30.0/24";
  #       primaryIp = "192.168.30.2";
  #       backupIp = "192.168.30.3";
  #       virtualIp = "192.168.30.1";
  #       enableDhcp = true;
  #       dhcpRangeStart = "192.168.30.50";
  #       dhcpRangeEnd = "192.168.30.150";
  #       isolated = true; # Isolate this VLAN
  #     }
  #   ];

  #   # --- WAN IP ---
  #   externalStaticIp = {
  #     address = "YOUR_STATIC_IP";
  #     prefixLength = 24; # Your prefix length
  #     gateway = "YOUR_GATEWAY_IP";
  #   };
  #   # Or set externalStaticIp = null; to use DHCP on WAN

  #   # --- DNS ---
  #   dnsServers = [ "9.9.9.9" "1.1.1.1" ]; # Override defaults if needed
  #   dnsCacheSize = 2000; # Customize DNS cache

  #   # --- DHCP ---
  #   keaDhcp4.enable = true;
  #   keaDhcp4.failover = mkIf config.${namespace}.hosts.base-router.vrrp.enable { # Enable failover only if VRRP is enabled
  #      # Parameters are mostly defaults, adjust if needed
  #      mclt = 1800; # Example override
  #   };
>>>>>>> Stashed changes

  #    # For self-hosted DHCP, change to:
  #    # dhcpMode = "internal";

<<<<<<< Updated upstream
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
=======
  #   # --- VRRP / Keepalived ---
  #   vrrp.enable = true; # Enable HA
  #   vrrp.virtualRouterIdBase = 50; # Customize base VRID
  #   vrrp.priority = if routerRole == "primary" then 150 else 100; # Explicit priorities
  #   # vrrp.authPass = "supersecret"; # Use authPassFile instead
  #   vrrp.authPassFile = config.sops.secrets."keepalived_vrrp_password".path;
  #   vrrp.keaFailoverPort = 647; # Ensure this matches Kea config if using failover

  #   # --- Firewall ---
  #   allowPingFromWan = false;
  #   portForwarding = [
  #     { sourcePort = 80; destination = "192.168.20.10"; protocol = "tcp"; description = "Web Server"; }
  #     { sourcePort = 443; destination = "192.168.20.10"; protocol = "tcp"; }
  #     { sourcePort = 1194; destination = "192.168.20.11"; destinationPort = 1194; protocol = "udp"; description = "OpenVPN"; }
  #   ];

  #   # --- Kernel ---
  #   extraKernelModules = [ "wireguard" ]; # Example
  #   extraSysctlSettings = {
  #     "net.core.somaxconn" = 1024; # Example custom sysctl
  #   };

  # };

  # # --- SOPS Configuration (Example) ---
  # sops.secrets."keepalived_vrrp_password" = {
  #     # mode = "0400"; # keepalived runs as root, default mode is fine
  #     # owner = config.users.users.keepalived.name; # Not needed if root reads it
  # };
  # # sops.secrets."root_password" = {};

  # # Disable NetworkManager as interfaces are manually configured by the router modules
  # networking.networkmanager.enable = false;
  };
>>>>>>> Stashed changes
}
