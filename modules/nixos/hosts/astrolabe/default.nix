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
  cfg = config.${namespace}.hosts.astrolabe;
  sops = config.sops;
in
{
  options.${namespace}.hosts.astrolabe = {
    enable = mkBoolOpt false "Whether to enable base astrolabe server configuration";
    allFeatures = mkBoolOpt true "Whether to enable all features. Set to false for safe boot mode with minimal services.";
    ipAddress = mkOpt types.str "" "Main Static management IP address with CIDR";
    interfaceMac = mkOpt types.str "" "Static IP Interface mac address";
    k8sNodeIp = mkOpt types.str "" "IP address for custom k8s node IP";
    k8sNodeIface = mkOpt types.str "" "Iface for k8s";
    k8sServerAddr =
      mkOpt types.str ""
        "Address of the server node to connect to (not needed for the first node).";
  };

  config = mkIf cfg.enable {
    # System dependencies
    # Boot config handled in system file

    # enable custom secrets
    sops.secrets = mkMerge [
      {
        k8s_token = {
          sopsFile = ./secrets.enc.yaml;
        };
      }
    ];

    # enable GPU drivers and firmware
    hardware.enableRedistributableFirmware = true;
    hardware.firmware = [ pkgs.linux-firmware ];
    hardware.cpu.amd.updateMicrocode = true;

    services.openssh = {
      enable = true;
      # Disable password-based authentication for security.
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false; # Disables keyboard-interactive auth, often a fallback for passwords.
        PermitRootLogin = "prohibit-password"; # Allows root login with a key, but not a password.
      };
    };

    ${namespace} = {

      system = {
        console-info.ip-display = enabled;
        nix-config = enabled;
      };

      suites = {
        monitoring = mkIf cfg.allFeatures {
          enable = true;
        };
      };

      services = {
        k8s = mkIf cfg.allFeatures {
          enable = true;
          tokenFile = sops.secrets.k8s_token.path;
          isFirstNode = false;
          nodeIp = cfg.k8sNodeIp;
          nodeIface = cfg.k8sNodeIface;
          serverAddr = cfg.k8sServerAddr;
          networkType = "standard";
          role = "agent"; # Worker/Agent node
          extraArgs = [
            "--node-label=gpu=strix-halo"
            "--node-label=tier=compute"
          ];
        };
      };

      virtualization = {
        docker = mkIf cfg.allFeatures { enable = true; };
      };

      hardware = {
        amdgpu = enabled;
        # Assuming AMD GPU Device Plugin for Kubernetes
        amdgpu-plugin = mkIf cfg.allFeatures { enable = true; };
      };

      networking = {
        tailscale = mkIf cfg.allFeatures {
          enable = true;
          ephemeral = false;
          extraArgs = [
            "--accept-dns=false"
            "--accept-routes=false"
            "--advertise-routes="
            "--snat-subnet-routes=true"
          ];
        };
      };
    };

    # Traditional networking configuration (minimal)
    networking = {
      firewall.allowedTCPPorts = [
        5201 # iperf
      ];
      useDHCP = false;
      interfaces = { };
      nameservers = [
        "172.16.1.1"
        "1.1.1.1"
        "9.9.9.9"
      ];
      enableIPv6 = false;
      networkmanager.enable = false;
    };

    # systemd-networkd configuration
    systemd.network = {
      enable = true;

      links."10-mgmnt" = {
        matchConfig.PermanentMACAddress = cfg.interfaceMac;
        linkConfig.Name = "mgmnt";
      };

      networks = {
        "11-mgmnt" = {
          matchConfig = {
            Name = "mgmnt";
          };
          networkConfig = {
            DHCP = "no";
            Gateway = "172.16.1.1";
            IPv6AcceptRA = "no";
          };
          address = [
            "${cfg.ipAddress}"
          ];
          routes = [
            {
              Gateway = "172.16.1.1";
              Destination = "0.0.0.0/0";
            }
          ];
        };
      };
    };
  };
}
