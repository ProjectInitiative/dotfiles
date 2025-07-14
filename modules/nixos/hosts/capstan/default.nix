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
    bonding = {
      mode = mkOpt (types.enum [ "none" "standard" "mellanox" ]) "none"
        "Type of bonding to configure. 'none' disables bonding.";

      members = mkOpt (types.listOf types.str) [ ] {
        description = "List of permanent MAC addresses of the interfaces to include in the bond.";
        example = ''[ "00:1A:2B:3C:4D:5E" "00:1A:2B:3C:4D:5F" ]'';
      };
      ipAddress = mkOpt types.str ""
        "Static IP address with CIDR for the bond interface (e.g., \"10.0.0.5/24\").";
    
      mellanoxPcieAddress = mkOpt types.str ""
        "PCIe address of the Mellanox card. Required only if mode is 'mellanox'.";
    };
    interfaceMac = mkOpt types.str "" "Static IP Interface mac address";
    gateway = mkOpt types.str "" "Default gateway";
    bcachefsInitDevice = mkOpt types.str "" "Device path for one of the bcachefs pool drives";
    mountpoint = mkOpt types.str "/mnt/pool" "Path to mount bcachefs pool";
    nvidiaSupport = mkBoolOpt false "Whether to enable nvidia GPU support";
    isFirstK8sNode = mkBoolOpt false "Whether node is the first in the cluster";
    k8sNodeIp = mkOpt types.str "" "IP address for custom k8s node IP";
    k8sNodeIface = mkOpt types.str "" "Iface for k8s";
    k8sServerAddr =
      mkOpt types.str ""
        "Address of the server node to connect to (not needed for the first node).";
    bondMembers =
      mkOpt (types.listOf types.str) [ ]
        "List of network interfaces to include in the bond";
  };

  config = mkIf cfg.enable {
    # Assertion to ensure Mellanox PCIe address is set when needed
    assertions = [
      {
        assertion = cfg.bonding.mode != "mellanox" || cfg.bonding.mellanoxPcieAddress != "";
        message = "When bonding mode is 'mellanox', `bonding.mellanoxPcieAddress` must be set.";
      }
    ];
    # enable custom secrets
    sops.secrets = mkMerge [
      {
        k8s_token = {
          sopsFile = ./secrets.enc.yaml;
        };
        jfs_backup_meta_password = { };
        jfs_backup_rsa_passphrase = { };
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
    boot.kernelModules = [
      "bcachefs"
      "drbd"
     ];
    # use latest kernel - required by bcachefs
    boot.kernelPackages = pkgs.linuxPackages_latest;

    # Late-mounting service
    # systemd.services.mount-bcachefs = {
    #   description = "Mount bcachefs test filesystem";
    #   path = [
    #     pkgs.bcachefs-tools
    #     pkgs.util-linux
    #     pkgs.gawk
    #   ];

    #   # Start after basic system services are up
    #   after = [
    #     "network.target"
    #     "local-fs.target"
    #     "multi-user.target"
    #   ];

    #   # Don't consider boot failed if this service fails
    #   wantedBy = [ "multi-user.target" ];

    #   # Service configuration
    #   serviceConfig = {
    #     Type = "oneshot";
    #     RemainAfterExit = true;
    #     ExecStartPre = "+${pkgs.coreutils}/bin/mkdir -p ${cfg.mountpoint}";
    #   };

    #   # The actual mount script
    #   script = ''
    #     # Mount the filesystem if not already mounted
    #     if ! mountpoint -q ${cfg.mountpoint}; then
    #       UUID=$(bcachefs show-super ${cfg.bcachefsInitDevice} | grep Ext | awk '{print $3}')
    #       mount -t bcachefs UUID=$UUID ${cfg.mountpoint}
    #     fi
    #   '';

    # };

    environment.systemPackages = with pkgs; [
      bcachefs-tools
      util-linux
      smartmontools
      lsof
      pciutils
      iperf3
      # k8s specific
      tpm2-tools
      tpm2-pkcs11
      opensc
      drbd
    ];

    fileSystems."/jfs-cache" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [
        "size=8G" # Set the size limit (adjust as needed)
        "mode=1777" # Permissions (1777 is standard for /tmp)
        "nosuid" # Disable setuid programs
        "nodev" # Disable device files
        # "noexec"        # Optional: Disable execution of binaries
      ];
    };

    fileSystems."/mnt/local-provisioner" = {
      device = "/mnt/pool/k8s";
      options = [ "bind" ];
    };


    # fileSystems."/mnt/pool" =
    #   { device = "UUID=27cac550-3836-765c-d107-51d27ab4a6e1";
    #     fsType = "bcachefs";
    #   };

    services.openssh.enable = true;

    projectinitiative = {

      suites = {
        attic = {
          enableClient = true;
        };
        bcachefs-utils = {
          enable = true;
          parentSubvolume = "/mnt/pool";
        };
        bcachefsFileOptions = {
          enable = true;
          jobs = {
            # This is a custom, descriptive name for your job.
            k8s-nvme-cache = {
        
              # The directory to apply options to.
              path = "/mnt/pool/k8s/nvme-cache";

              # Set the schedule using a systemd OnCalendar expression.
              onCalendar = "daily"; # Runs at 00:00 every day.

              # The bcachefs file options to set.
              fileOptions = {
                background_target = "cache";
                foreground_target = "cache";
                promote_target    = "cache";
              };
            };
          };
        };
      };

      services = {

        eternal-terminal = enabled;

        health-reporter = {
          enable = true;
          telegramTokenPath = config.sops.secrets.health_reporter_bot_api_token.path;
          telegramChatIdPath = config.sops.secrets.telegram_chat_id.path;
          excludeDrives = [
            "loop"
            "ram"
            "sr"
          ]; # Default exclusions
          reportTime = "08:00"; # Send report at 8 AM
        };

        juicefs = {
          enable = true;
          mounts = {
            backup = {
              enable = true;
              mountPoint = "/mnt/jfs/backup";
              metaUrl = "redis://172.16.1.18:6380/1";
              metaPasswordFile = sops.secrets.jfs_backup_meta_password.path;
              rsaPassphraseFile = sops.secrets.jfs_backup_rsa_passphrase.path;
              cacheDir = "/jfs-cache";
              region = "da";
              maxUploads = 20;

              # Add any additional options as needed
              # extraoptions = {
              #   "heartbeat" = "12";
              #   "attr-cache" = "1";
              #   "entry-cache" = "1";
              #   "dir-entry-cache" = "1";
              # };
            };

          };
        };

        k8s = {
          enable = true;
          tokenFile = sops.secrets.k8s_token.path;
          isFirstNode = cfg.isFirstK8sNode;
          nodeIp = cfg.k8sNodeIp;
          nodeIface = cfg.k8sNodeIface;
          serverAddr = cfg.k8sServerAddr;
          networkType = "standard";
          role = "server";
          extraArgs = [
            # TLS configuration
            "--tls-san=172.16.1.50"

            # Security
            "--secrets-encryption"
            "--disable=traefik"
            "--disable local-storage"
          ];
          kubeVip = {
            enable = cfg.isFirstK8sNode;
            version = "v0.8.9";
            vip = "172.16.1.50";
            interface = "mgmnt";
          };
        };
      };

      system = {
        # Enable common base modules
        console-info.ip-display = enabled;
        nix-config = enabled;
      };

      networking = {
        mellanox = {
          enable = mkIf (cfg.bonding.mode == "mellanox") true;
          interfaces = [
            {
              device = "Mellanox Connect X-3";
              pciAddress = cfg.bonding.mellanoxPcieAddress;
              nics = [
                # "enp5s0"
                # "enp5s0d1"
                # "vmbr4"
              ] ++ cfg.bonding.members;
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
          ephemeral = false;
          extraArgs = [
            "--accept-dns=false"
            # "--accept-routes=true"
            # "--advertise-routes=10.0.0.0/24"
            # "--snat-subnet-routes=false"
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
      # Disable DHCP globally
      useDHCP = false;

      # Clear interfaces (managed by systemd-networkd)
      interfaces = { };

      # Keep DNS configuration
      nameservers = [
        "172.16.1.1"
        "1.1.1.1"
        "9.9.9.9"
      ];

      # Keep global networking settings
      # defaultGateway = "172.16.1.1";
      enableIPv6 = false;

      # Disable NetworkManager if you're using it
      networkmanager.enable = false;
    };

    # systemd-networkd configuration
    systemd.network = {
      # Enable systemd-networkd
      enable = true;

      # Bond configuration (conditionally included)
      netdevs = lib.mkIf (cfg.bonding.mode != "none") {
        "20-bond0" = {
          netdevConfig = {
            Name = "bond0";
            Kind = "bond";
          };
          bondConfig = {
            Mode = "802.3ad";
            MIIMonitorSec = "100ms";
            TransmitHashPolicy = "layer3+4";
            LACPTransmitRate = "fast";
          };
        };
      };

      links."10-mgmnt" = {
        matchConfig.PermanentMACAddress = cfg.interfaceMac;
        linkConfig.Name = "mgmnt";
      };

      # Network configurations - combining main interface and conditional bond setup
      networks = lib.mkMerge [
        # Main interface configuration (always included)
        {
          "11-mgmnt" = {
            matchConfig = {
              Name = "mgmnt";
            };
            networkConfig = {
              DHCP = "no";
              Gateway = "172.16.1.1";
              DNS = "172.16.1.1 1.1.1.1 9.9.9.9";
              IPv6AcceptRA = "no";
            };
            address = [
              "${cfg.ipAddress}"
            ];
            # Add explicit route configuration
            routes = [
              {
                Gateway = "172.16.1.1";
                Destination = "0.0.0.0/0";
              }
            ];
          };
        }

        # Bond-related interfaces (conditionally included)
        (lib.mkIf (cfg.bonding.mode != "none") (
          # Merge separate bond member configurations for each interface
          lib.mkMerge [
            # Dynamic bond member configurations from bondMembers list
            (lib.listToAttrs (
              map (mac:
                let
                  # Sanitize MAC address for the systemd unit name
                  sanitizedMac = lib.replaceStrings [ ":" ] [ "-" ] mac;
                in
                {
                  # e.g., name = "30-bond-member-00-1A-2B-3C-4D-5E"
                  name = "30-bond-member-${sanitizedMac}";
                  value = {
                    matchConfig = {
                      # Match the interface by its permanent hardware address
                      PermanentMACAddress = mac;
                    };
                    networkConfig = {
                      Bond = "bond0";
                    };
                    linkConfig = {
                      MTUBytes = "9000";
                    };
                  };
                }) cfg.bonding.members
            ))

            # Bond interface configuration
            {
              "40-bond0" = {
                matchConfig = {
                  Name = "bond0";
                };
                networkConfig = {
                  DHCP = "no";
                  IPv6AcceptRA = "no";
                };
                # MTU needs to be in linkConfig, not networkConfig
                linkConfig = {
                  MTUBytes = "9000";
                };
                address = [
                  "${cfg.bonding.ipAddress}/24"
                ];
              };
            }
          ])
        )
      ];
    };

  };
}
