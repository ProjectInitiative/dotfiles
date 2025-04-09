{
  config,
  lib,
  pkgs,
  # namespace, # No longer needed for helpers
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.hosts.cargohold;
in
{
  options.${namespace}.hosts.cargohold = with types; {
    enable = mkEnableOption "base cargohold NAS configuration"; # Use standard mkEnableOption
    ipAddress = mkOption { type = types.str; default = "192.168.1.100/24"; description = "Static management IP address with CIDR"; }; # Use standard mkOption
    interface = mkOption { type = types.str; default = "eth0"; description = "Network interface for static IP"; }; # Use standard mkOption
    gateway = mkOption { type = types.str; default = "192.168.1.1"; description = "Default gateway"; }; # Use standard mkOption
    bcachefsMountpoint = mkOption { type = types.str; default = "/mnt/storage"; description = "Path to mount bcachefs pool"; }; # Use standard mkOption
    # Add more NAS specific options here later if needed (e.g., Samba shares)
  };

  config = mkIf cfg.enable {
    # Base system packages
    environment.systemPackages = with pkgs; [
      bcachefs-tools
      smartmontools
      lsof
      pciutils
      iperf3
      # Add NAS related tools like samba, nfs-utils if needed
    ];

    # Enable bcachefs support
    boot.supportedFilesystems = [ "bcachefs" ];
    boot.kernelModules = [ "bcachefs" ];
    # Consider using latest kernel if needed for bcachefs features
    boot.kernelPackages = pkgs.linuxPackages_latest;
    boot.kernelParams = [ "nomodeset" ];
    console.enable = true;
    # enable GPU drivers
    hardware.enableRedistributableFirmware = true;
    hardware.firmware = [ pkgs.linux-firmware ];

    # Enable SSH access
    services.openssh = {
      enable = true;
      settings = {
      };
    };

    # Networking using systemd-networkd
    networking = {
      useDHCP = true; # Disable global DHCP
      # interfaces = { }; # Clear interfaces managed elsewhere
      nameservers = [
        cfg.gateway # Use gateway as primary DNS
        "1.1.1.1" # Cloudflare DNS
        "9.9.9.9" # Quad9 DNS
      ];
      # defaultGateway = cfg.gateway; # Set via systemd-networkd route
      # firewall.allowedTCPPorts = [
      #   22 # SSH
      #   5201 # iperf
      #   # Add ports for NAS services (e.g., Samba: 139, 445)
      # ];
      networkmanager.enable = false; # Ensure NetworkManager is disabled
    };

    systemd.network = {
      enable = false;
      networks."10-${cfg.interface}" = {
        matchConfig.Name = cfg.interface;
        networkConfig = {
          DHCP = "no";
          Address = cfg.ipAddress;
          Gateway = cfg.gateway;
          DNS = config.networking.nameservers; # Use nameservers defined above
          IPv6AcceptRA = "no";
        };
        # Explicit default route
        routes = [
          {
            Gateway = cfg.gateway;
            Destination = "0.0.0.0/0";
          }
        ];
      };
    };

    # Enable common project modules if needed
    projectinitiative = {
      suites = {
        bcachefs-utils.enable = true; # Use standard boolean
      };
      system = {
        console-info.ip-display.enable = true; # Use standard boolean

        bcachefs-kernel = {
          enable = true; # Standard boolean
          branch = "c79cf4111930c22487840d1332ee1d44e1c31707"; # Or specify a specific commit hash
          sourceHash = "sha256-uVo7X8/1akJxgO0ERu/41+XmK7l1uRAZuKYJV4mNQAo=";
          debug = true;
        };
        bcachefs-module = {
          enable = false;
          rev = ""; # Or specify a specific commit hash
          hash = "";
          debug = true;
        };

      };
      networking.tailscale = {
        enable = true; # Example: Enable Tailscale
        ephemeral = false;
        extraArgs = [ "--accept-routes" ];
      };
      # Add other services like Samba, NFS configuration here
      # services.samba = { enable = true; /* ... */ };
    };

    # Set the state version
    system.stateVersion = "24.05"; # Adjust as needed
  };
}
