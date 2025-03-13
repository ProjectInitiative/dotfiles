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
  cfg = config.${namespace}.hosts.capstan;
  sops = config.sops;
in
{
  options.${namespace}.hosts.capstan = {
    enable = mkBoolOpt false "Whether to enable base capstan server configuration";
    # hostname = mkOpt types.str "" "Hostname for the server";
    ipAddress = mkOpt types.str "" "Main Static management IP address with CIDR";
    enableMlx = mkBoolOpt false "Temp var to disable mellanox config";
    mlxIpAddress = mkOpt types.str "" "Mellanox Static IP address";
    interface = mkOpt types.str "" "Static IP Interface";
    gateway = mkOpt types.str "" "Default gateway";
    bcachefsInitDevice = mkOpt types.str "" "Device path for one of the bcachefs pool drives";
    mountpoint = mkOpt types.str "/mnt/pool" "Path to mount bcachefs pool";
    nvidiaSupport = mkBoolOpt false "Whether to enable nvidia GPU support";
    isFirstK8sNode = mkBoolOpt false "Whether node is the first in the cluster";
    k8sServerAddr =
      mkOpt types.str ""
        "Address of the server node to connect to (not needed for the first node).";
  };

  config = mkIf cfg.enable {
    # enable custom secrets
    sops.secrets = mkMerge [
      {
        k8s_token = {
          sopsFile = ./secrets.enc.yaml;
        };
      }
    ];

    # enable GPU drivers
    hardware.enableRedistributableFirmware = true;
    hardware.firmware = [ pkgs.linux-firmware ];
    # boot.kernel.sysctl = {
    #   "kernel.sysrq" = 1;
    # };
    # # Enable the console
    # console = {
    #   enable = true;
    #   keyMap = "us"; # Or your preferred keymap
    # };
    # advanced bcachefs support
    boot.supportedFilesystems = [ "bcachefs" ];
    boot.kernelModules = [ "bcachefs" ];
    # use latest kernel - required by bcachefs
    boot.kernelPackages = pkgs.linuxPackages_latest;

    # Late-mounting service
    systemd.services.mount-bcachefs = {
      description = "Mount bcachefs test filesystem";
      path = [
        pkgs.bcachefs-tools
        pkgs.util-linux
        pkgs.gawk
      ];

      # Start after basic system services are up
      after = [
        "network.target"
        "local-fs.target"
        "multi-user.target"
      ];

      # Don't consider boot failed if this service fails
      wantedBy = [ "multi-user.target" ];

      # Service configuration
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "+${pkgs.coreutils}/bin/mkdir -p ${cfg.mountpoint}";
      };

      # The actual mount script
      script = ''
        # Mount the filesystem if not already mounted
        if ! mountpoint -q ${cfg.mountpoint}; then
          UUID=$(bcachefs show-super ${cfg.bcachefsInitDevice} | grep Ext | awk '{print $3}')
          mount -t bcachefs UUID=$UUID ${cfg.mountpoint}
        fi
      '';

    };

    environment.systemPackages = with pkgs; [
      bcachefs-tools
      util-linux
      smartmontools
      lsof
      pciutils
    ];

    services.openssh.enable = true;

    projectinitiative = {

      services = {
        k8s = {
          enable = true;
          tokenFile = sops.secrets.k8s_token.path;
          isFirstNode = cfg.isFirstK8sNode;
          serverAddr = cfg.k8sServerAddr;
          networkType = "cilium";
          role = "server";
          extraArgs = [
            # TLS configuration
            "--tls-san=172.16.1.50"

            # Security
            "--secrets-encryption"
          ];
          kubeVip = {
            enable = cfg.isFirstK8sNode;
            vip = "172.16.1.50";
            interface = cfg.interface;
          };
        };
      };

      system = {
        # Enable common base modules
        console-info.ip-display = enabled;
      };

      networking = {
        mellanox = {
          enable = cfg.enableMlx;
          interfaces = [
            {
              device = "Mellanox Connect X-3";
              pciAddress = "0000:05:00.0";
              nics = [
                "enp5s0"
                "enp5s0d1"
                "bond0"
                # "vmbr4"
              ];
              mlnxPorts = [
                "1"
                "2"
              ];
              mode = "eth";
            }
            # You can add more interfaces as needed
          ];
        };
        tailscale = {
          enable = true;
          extraArgs = [
            "--accept-dns=false"
          ];
        };
      };

    };

    # Common network configuration
    networking = {
      # Interface configuration
      interfaces = {
        ${cfg.interface} = {
          useDHCP = false;
          ipv4.addresses = [
            {
              address = lib.removeSuffix "/24" cfg.ipAddress;
              prefixLength = 24;
            }
          ];
        };
        bond0 = mkIf cfg.enableMlx {
          useDHCP = false;
          ipv4.addresses = [
            {
              address = cfg.mlxIpAddress;
              prefixLength = 24;
            }
          ];
        };
      };

      # Bond configuration
      bonds.bond0 = mkIf cfg.enableMlx {
        interfaces = [
          "enp5s0"
          "enp5s0d1"
        ];
        driverOptions = {
          mode = "802.3ad";
          miimon = "100";
          xmit_hash_policy = "layer3+4";
          lacp_rate = "fast";
        };
      };

      # Gateway, DNS, and general networking settings
      defaultGateway = "172.16.1.1";
      nameservers = [
        "172.16.1.1"
        "1.1.1.1"
        "9.9.9.9"
      ];
      enableIPv6 = false;
    };

    system.stateVersion = "24.05"; # Did you read the comment?
  };
}
