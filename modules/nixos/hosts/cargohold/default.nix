{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.cargohold;
in
{
  options.${namespace}.hosts.cargohold = {
    enable = mkBoolOpt false "Whether to enable base cargohold NAS configuration";
    ipAddress = mkOpt types.str "192.168.1.100/24" "Static management IP address with CIDR"; # Example IP
    interface = mkOpt types.str "eth0" "Network interface for static IP"; # Example interface
    gateway = mkOpt types.str "192.168.1.1" "Default gateway"; # Example gateway
    bcachefsMountpoint = mkOpt types.str "/mnt/storage" "Path to mount bcachefs pool";
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
    # boot.kernelPackages = pkgs.linuxPackages_latest;

    # Enable SSH access
    services.openssh = {
      enable = true;
      settings = {
        # Harden SSH config if desired
        # PermitRootLogin = "no";
        # PasswordAuthentication = false;
      };
    };

    # Networking using systemd-networkd
    networking = {
      useDHCP = false; # Disable global DHCP
      interfaces = { }; # Clear interfaces managed elsewhere
      nameservers = [
        cfg.gateway # Use gateway as primary DNS
        "1.1.1.1" # Cloudflare DNS
        "9.9.9.9" # Quad9 DNS
      ];
      # defaultGateway = cfg.gateway; # Set via systemd-networkd route
      firewall.allowedTCPPorts = [
        22 # SSH
        5201 # iperf
        # Add ports for NAS services (e.g., Samba: 139, 445)
      ];
      networkmanager.enable = false; # Ensure NetworkManager is disabled
    };

    systemd.network = {
      enable = true;
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
        bcachefs-utils = enabled;
      };
      system = {
        console-info.ip-display = enabled;
      };
      networking.tailscale = {
        enable = true; # Example: Enable Tailscale
        ephemeral = false;
        extraArgs = [ "--accept-dns=false" ];
      };
      # Add other services like Samba, NFS configuration here
      # services.samba = { enable = true; /* ... */ };
    };

    # Set the state version
    system.stateVersion = "24.05"; # Adjust as needed
  };
}
