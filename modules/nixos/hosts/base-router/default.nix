# Example usage in a host configuration (e.g., /etc/nixos/hosts/my-primary-router/configuration.nix)
{ config, pkgs, lib, namespace, ... }:

{
  imports = [
    # Import your custom module containing the base-router definition
    # Adjust the path as needed relative to this configuration file
    ../../../../../modules/nixos/hosts/base-router/default.nix

    # Import sops module if using encrypted secrets for VRRP password
    # ./secrets.nix # Example path to sops configuration
  ];

  # Assuming 'namespace = "mycfg";' is set elsewhere (e.g., in your flake.nix)
  # If not using a namespace, adjust the paths accordingly (e.g., config.hosts.base-router)

  # Enable and configure the base-router module
  mycfg.hosts.base-router = {
    enable = true;
    wanInterface = "eth0"; # Your WAN network interface
    lanInterface = "br0";  # Your LAN bridge/interface (VLANs will be tagged on this)

    routerRole = "primary"; # Configure this host as the primary router

    managementVlan = {
      id = 1; # Untagged management traffic on lanInterface (br0)
      network = "192.168.1.0/24";
      virtualIp = "192.168.1.1";   # Shared IP for the active router
      primaryIp = "192.168.1.2";   # This router's IP
      backupIp = "192.168.1.3";    # The other router's IP
      enableDhcp = false;          # Typically no DHCP for management
    };

    vlans = [
      {
        id = 10;
        name = "Trusted LAN";
        network = "192.168.10.0/24";
        virtualIp = "192.168.10.1";
        primaryIp = "192.168.10.2";
        backupIp = "192.168.10.3";
        enableDhcp = true;           # Provide DHCP on this VLAN
        dhcpRangeStart = "192.168.10.100";
        dhcpRangeEnd = "192.168.10.200";
        isolated = false;            # Allow communication with other non-isolated VLANs
      }
      {
        id = 20;
        name = "IoT Devices";
        network = "192.168.20.0/24";
        virtualIp = "192.168.20.1";
        primaryIp = "192.168.20.2";
        backupIp = "192.168.20.3";
        enableDhcp = true;
        dhcpRangeStart = "192.168.20.100";
        dhcpRangeEnd = "192.168.20.200";
        isolated = true;             # Block traffic between IoT and other VLANs (e.g., Trusted LAN)
      }
      {
        id = 30;
        name = "Guest Network";
        network = "192.168.30.0/24";
        virtualIp = "192.168.30.1";
        primaryIp = "192.168.30.2";
        backupIp = "192.168.30.3";
        enableDhcp = true;
        dhcpRangeStart = "192.168.30.50";
        dhcpRangeEnd = "192.168.30.150";
        isolated = true;             # Block traffic between Guest and other VLANs
      }
    ];

    enableIPv6 = true; # Enable IPv6 features (forwarding, RA, etc.)
    dnsServers = [ "1.1.1.1" "9.9.9.9" ]; # Upstream DNS servers

    # Configure WAN connection type
    externalStaticIp = null; # Use DHCP for WAN IP address
    # Or define a static IP:
    # externalStaticIp = {
    #   address = "YOUR_STATIC_WAN_IP";
    #   prefixLength = 24; # Your WAN subnet prefix length
    #   gateway = "YOUR_ISP_GATEWAY_IP";
    # };

    allowPingFromWan = false; # Block pings coming from the internet

    portForwarding = [
      { sourcePort = 8080; destination = "192.168.10.50"; destinationPort = 80; protocol = "tcp"; description = "Forward port 8080 to internal web server"; }
      # Add more port forwarding rules here
    ];

    # Configure Kea DHCP server
    keaDhcp4 = {
      enable = true; # Enable Kea for the VLANs configured above with enableDhcp=true
      failover = {
        # Kea failover settings (defaults are often okay)
        # maxUnackedUpdates = 10;
        # maxAckDelay = 1000; # milliseconds
        # mclt = 3600; # seconds
      };
    };

    # Configure Dnsmasq DNS cache
    dnsCacheSize = 1500; # Increase cache size

    # Configure VRRP (Keepalived) for High Availability
    vrrp = {
      enable = true;
      virtualRouterIdBase = 50; # Base ID, ensure it's unique in your network segment
      priority = 150; # Higher value means more preferred (Primary > Backup)
      # Use an encrypted password file managed by sops
      authPassFile = config.sops.secrets."keepalived_vrrp_password".path;
      # Or use plain text (less secure):
      # authPass = "your_plain_text_vrrp_password";

      # Optional scripts to run on state changes
      # notifyMasterScript = "${pkgs.runtimeShell} -c '/usr/local/bin/notify-master.sh'";
      # notifyBackupScript = "${pkgs.runtimeShell} -c '/usr/local/bin/notify-backup.sh'";
    };

    # Optional: Load extra kernel modules or set sysctl parameters
    # extraKernelModules = [ "wireguard" ];
    # extraSysctlSettings = {
    #   "net.core.somaxconn" = 1024;
    # };
  };

  # --- Other Host-Specific Settings ---

  networking.hostName = "primary-router"; # Set the hostname

  # Define the LAN bridge if you specified one in lanInterface
  networking.bridges.br0.interfaces = [ "eth1" "eth2" ]; # List physical interfaces part of the LAN bridge

  # Example sops configuration (if using sops for secrets)
  # sops.secrets."keepalived_vrrp_password" = {
  #   # mode = "0400"; # Restrict permissions
  #   # owner = config.users.users.keepalived.name; # Set owner to keepalived user
  # };

  # Ensure keepalived user/group exist if setting owner for sops secret
  # users.users.keepalived.isSystemUser = true;
  # users.groups.keepalived = {};

  # Ensure necessary packages for bridging are present
  environment.systemPackages = with pkgs; [ bridge-utils ];

  # System state version (important!)
  system.stateVersion = "23.11"; # Or your current NixOS version
}
