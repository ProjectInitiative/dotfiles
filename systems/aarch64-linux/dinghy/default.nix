# nom build .\#nixosConfigurations.dinghy.config.system.build.sdImage

{
  config,
  inputs,
  pkgs,
  lib,
  modulesPath,
  namespace,
  ...
}:
let
  # Define the RAID storage mount point in one place
  storageMountPoint = "/mnt/pool";
  # Create files in the nix store
  hostSSHFile = pkgs.writeText "ssh_host_ed25519_key" config.sensitiveNotSecret.dinghy_private_ssh_key;
  hostSSHPubFile = pkgs.writeText "ssh_host_ed25519_key.pub" config.sensitiveNotSecret.dinghy_public_ssh_key;
in
{
  imports = with inputs.nixos-hardware.nixosModules; [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
    # (modulesPath + "/installer/sd-card/sd-image-aarch64-new-kernel.nix")
    raspberry-pi-4
  ];

  hardware.enableAllHardware = lib.mkForce false;
  boot.supportedFilesystems.zfs = lib.mkForce false;

  sdImage.compressImage = false;

  hardware.raspberry-pi."4" = {
    gpio.enable = true;
    pwm0.enable = true;
    # i2c0.enable = true;
    i2c1.enable = true;
  };

  hardware.rockpi-quad = {
    enable = true;
    # Optional: Customize settings (see flake.nix for options)
    settings = {
      fan.lv0 = 40;
      oled."f-temp" = false;
    };
  };

  environment.etc = {
    "ssh/ssh_host_ed25519_key" = {
      source = hostSSHFile;
      mode = "0600";
      user = "root";
      group = "root";
    };

    "ssh/ssh_host_ed25519_key.pub" = {
      source = hostSSHPubFile;
      mode = "0644";
      user = "root";
      group = "root";
    };
  };

  # Explicitly call development module
  home-manager = {
    backupFileExtension = "backup";
    users.kylepzak.${namespace} = {
      suites = {
        development.enable = true;
      };
    };

  };

  projectinitiative = {
    suites = {
      # TODO: fix this
      development.enable = true;
      attic = {
        enableClient = true;
      };
    };

    services = {
      eternal-terminal.enable = true;
      monitoring = {
        enable = true;
        openFirewall = true;

        # Enable the Prometheus server on this node
        prometheus = {
          enable = true;
          retentionTime = "90d"; # Keep data for 90 days

          # Define jobs to scrape other nodes
          scrapeConfigs = {
            # A job named 'nodes' to scrape all your other servers
            nodes = {
              targets = [
                "127.0.0.1:9100"
                "172.16.1.51:9100"
                "172.16.1.52:9100"
                "172.16.1.53:9100"
                "openwrt:9100"
                "cargohold:9100"
                "lepotato:9100"
                "stormjib:9100"
                "lighthouse-yul-1:9100"
                "lighthouse-yul-2:9100"
              ];
            };
            garage = {
              targets = [
                "172.16.1.51:31630"
                "172.16.1.52:31630"
                "172.16.1.53:31630"
              ];
            };
            # A job for scraping smartctl data if it's on a different port/host
            smart-devices = {
              targets = [
                "127.0.0.1:9633"
                "172.16.1.51:9633"
                "172.16.1.52:9633"
                "172.16.1.53:9633"
                "cargohold:9633"
              ];
            };
            speedtest = {
              targets = [ "openwrt:9469" ];
              extraConfig = {
                metrics_path = "/probe";
                params = {
                  script = [ "speedtest" ];
                };
                scrape_interval = "60m";
                scrape_timeout = "90s";
              };
            };

          };
        };

        # Add the Loki server
        loki = {
          enable = true;
          # Example configuration: using the default configuration
          config = {
            auth_enabled = false;

            limits_config = {
              allow_structured_metadata = false;
              volume_enabled = true;
            };

            # Centralized configuration for components
            common = {
              path_prefix = "${storageMountPoint}/loki";
              replication_factor = 1;
              # Defines the storage backend used by all components.
              storage = {
                filesystem = {
                  chunks_directory = "${storageMountPoint}/loki/chunks";
                  rules_directory = "${storageMountPoint}/loki/rules";
                };
              };
              # Required for single-node operation.
              ring = {
                instance_addr = "127.0.0.1";
                kvstore = {
                  store = "inmemory";
                };
              };
            };

            schema_config = {
              configs = [
                {
                  from = "2024-01-01";
                  store = "boltdb-shipper";
                  object_store = "filesystem"; # This must match the storage type in 'common'
                  schema = "v12";
                  index = {
                    prefix = "index_";
                    period = "24h";
                  };
                }
              ];
            };

            storage_config = {
              boltdb_shipper = {
                active_index_directory = "${storageMountPoint}/loki/index";
                cache_location = "${storageMountPoint}/loki/cache";
                cache_ttl = "24h";
                # Note: 'shared_store' is removed; it's now handled by the 'common.storage' block.
              };
            };

            compactor = {
              working_directory = "${storageMountPoint}/loki/compactor";
              # Note: 'shared_store' is removed; it's now handled by the 'common.storage' block.
            };
          };

        };

        # Add Promtail to scrape local logs and send them to Loki
        promtail = {
          enable = false;
          scrapeConfigs = [
            {
              job_name = "journal";
              journal = {
                labels = {
                  job = "systemd-journal";
                  host = "dinghy";
                };
              };
              relabel_configs = [
                {
                  source_labels = [ "__journal__systemd_unit" ];
                  target_label = "unit";
                }
              ];
            }
          ];
        };

        # Enable Grafana on this node
        grafana = {
          enable = true;
        };

        # Also enable exporters on this monitoring server itself.
        # The server will automatically pick these up under the 'self' job.
        exporters = {
          node.enable = true;
          smartctl.enable = true;
        };
      };
    };
    networking = {
      tailscale = {
        enable = true;
        ephemeral = false;
        extraArgs = [
          "--accept-dns=true"
          "--accept-routes=true"
        ];
      };
    };
    system = {
      console-info.ip-display.enable = true;
    };
  };

  # boot.loader = {
  #   grub.enable = false;
  #   systemd-boot.enable = false;  # Disable systemd-boot
  #   generic-extlinux-compatible.enable = true;  # Enable extlinux bootloader
  # };

  services.openssh.enable = true;
  console.enable = true;
  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom
    mdadm
  ];

  # Single networking attribute set
  networking = {
    networkmanager = {
      enable = false;
      wifi.powersave = false;
    };
    useDHCP = true;
    interfaces = { }; # Clear interfaces - managed by systemd-networkd
    useNetworkd = true;

    # usePredictableInterfaceNames = false;
  };

  # --- Late-boot MDADM RAID Assembly and Mount ---

  # This service runs late in the boot process, after the system is up.
  # It assembles the RAID array and then mounts it.
  systemd.services.storage-mount = {
    description = "Assemble and mount the storage RAID array";

    # Run after the main system is up and running.
    after = [ "rockpi-quad.service" ];
    # Be part of the local filesystem setup target.
    wantedBy = [ "local-fs.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      # Using 'writeShellScript' allows us to run multiple commands safely.
      # `set -e` ensures the script exits immediately if any command fails.
      ExecStart = pkgs.writeShellScript "mount-storage" ''
        set -e
        echo "Waiting for RAID devices to appear..."
        DEVICES_TO_WAIT_FOR=("/dev/sda" "/dev/sdb" "/dev/sdc" "/dev/sdd")
        TIMEOUT=30
        for i in $(seq $TIMEOUT); do
          # Check if all devices exist as block devices
          if [ -b "''${DEVICES_TO_WAIT_FOR[0]}" ] && \
             [ -b "''${DEVICES_TO_WAIT_FOR[1]}" ] && \
             [ -b "''${DEVICES_TO_WAIT_FOR[2]}" ] && \
             [ -b "''${DEVICES_TO_WAIT_FOR[3]}" ]; then
            echo "All RAID devices found."
            break
          fi

          # If we hit the timeout, exit with an error
          if [ $i -eq $TIMEOUT ]; then
            echo "Error: Timed out waiting for RAID devices." >&2
            exit 1
          fi
          sleep 1
        done
        echo "Assembling RAID array /dev/md0..."
        # Use the explicit command to assemble the array from specific devices
        ${pkgs.mdadm}/bin/mdadm --assemble --run --verbose /dev/md0 /dev/sda /dev/sdb /dev/sdc /dev/sdd --force

        echo "Mounting /dev/md0 to ${storageMountPoint}..."
        ${pkgs.coreutils}/bin/mkdir -p ${storageMountPoint}
        ${pkgs.util-linux}/bin/mount /dev/md0 ${storageMountPoint}
        echo "Storage mounted."
      '';

      # Defines how to unmount and stop the array when the service is stopped.
      ExecStop = pkgs.writeShellScript "unmount-storage" ''
        set -e
        echo "Unmounting ${storageMountPoint}..."
        ${pkgs.util-linux}/bin/umount -l ${storageMountPoint}

        echo "Stopping RAID array /dev/md0..."
        ${pkgs.mdadm}/bin/mdadm --stop /dev/md0
        echo "Storage stopped."
      '';
    };
  };

  systemd.services.prometheus = {
    after = [ "storage-mount.service" ];
    requires = [ "storage-mount.service" ];
  };

  systemd.services.loki = {
    after = [ "storage-mount.service" ];
    requires = [ "storage-mount.service" ];
  };

  # # Define the filesystem on the RAID array to be mounted.
  # fileSystems."/mnt/pool" = {
  #   # This should be the device path for your assembled RAID array.
  #   # You can verify this with `cat /proc/mdstat`. It's often /dev/md0 or /dev/md127.
  #   device = "/dev/md0";

  #   # Replace "ext4" with the actual filesystem type on your array (e.g., btrfs, xfs).
  #   fsType = "ext4";

  #   # The 'nofail' option is recommended. It prevents your system
  #   # from failing to boot if the array cannot be assembled.
  #   options = [ "defaults" "nofail" ];
  # };

  # Use tmpfs for temporary files
  # fileSystems."/tmp" = {
  #   device = "tmpfs";
  #   fsType = "tmpfs";
  #   options = [
  #     "nosuid"
  #     "nodev"
  #     "relatime"
  #     "size=256M"
  #   ];
  # };

  # journald settings to reduce writes
  # services.journald.extraConfig = ''
  #   Storage=volatile
  #   RuntimeMaxUse=64M
  #   SystemMaxUse=64M
  # '';

  # disko = {
  #   devices = {

  #     # Cross-compilation settings
  #     # imageBuilder = {
  #     #   enableBinfmt = true;
  #     #   pkgs = pkgs;
  #     #   kernelPackages = pkgs.legacyPackages.x86_64-linux.linuxPackages_latest;
  #     # };
  #     disk = {
  #       sd = {
  #         imageSize = "32G";
  #         imageName = "stormjib-rpi";
  #         device = "/dev/mmcblk0";
  #         type = "disk";
  #         content = {
  #           type = "gpt";
  #           partitions = {
  #             # Boot partition - fixed 256MB size
  #             boot = {
  #               name = "boot";
  #               size = "256M"; # Fixed size for boot
  #               type = "EF00"; # EFI System Partition
  #               content = {
  #                 type = "filesystem";
  #                 format = "vfat";
  #                 mountpoint = "/boot";
  #                 mountOptions = [
  #                   "defaults"
  #                   "noatime"
  #                 ];
  #               };
  #             };

  #             # Root partition - read-only
  #             root = {
  #               name = "root";
  #               size = "20%"; # Percentage of remaining space
  #               content = {
  #                 type = "filesystem";
  #                 format = "ext4";
  #                 mountpoint = "/";
  #                 mountOptions = [
  #                   "defaults"
  #                   "noatime"
  #                 ]; # "ro" ]; # Read-only mount
  #               };
  #             };

  #             # Nix store partition
  #             nix = {
  #               name = "nix";
  #               size = "35%"; # Percentage of remaining space
  #               content = {
  #                 type = "filesystem";
  #                 format = "ext4";
  #                 mountpoint = "/nix";
  #                 mountOptions = [
  #                   "defaults"
  #                   "noatime"
  #                 ];
  #               };
  #             };

  #             # Logs partition
  #             logs = {
  #               name = "logs";
  #               size = "10%"; # Percentage of remaining space
  #               content = {
  #                 type = "filesystem";
  #                 format = "ext4";
  #                 mountpoint = "/var/log";
  #                 mountOptions = [
  #                   "defaults"
  #                   "noatime"
  #                   "commit=600"
  #                 ];
  #               };
  #             };

  #             # Persistent data partition
  #             data = {
  #               name = "data";
  #               size = "100%"; # Use all remaining space
  #               content = {
  #                 type = "filesystem";
  #                 format = "ext4";
  #                 mountpoint = "/var/lib";
  #                 mountOptions = [
  #                   "defaults"
  #                   "noatime"
  #                   "commit=600"
  #                 ];
  #               };
  #             };
  #           };
  #         };
  #       };
  #     };
  #   };
  # };

}
