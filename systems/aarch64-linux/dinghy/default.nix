# nom build .\#nixosConfigurations.dinghy.config.system.build.sdImage

{
  config,
  inputs,
  pkgs,
  lib,
  modulesPath,
  ...
}:
let
  # Create files in the nix store
  hostSSHFile = pkgs.writeText "ssh_host_ed25519_key" config.sensitiveNotSecret.dinghy_private_ssh_key;
  hostSSHPubFile = pkgs.writeText "ssh_host_ed25519_key.pub" config.sensitiveNotSecret.dinghy_public_ssh_key;
in
{
  imports = with inputs.nixos-hardware.nixosModules; [
    (modulesPath + "/installer/scan/not-detected.nix")
    # (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
    (modulesPath + "/installer/sd-card/sd-image-aarch64-new-kernel.nix")
    # raspberry-pi-4
  ];

  boot.supportedFilesystems.zfs = lib.mkForce false;

  sdImage.compressImage = false;

  # hardware.deviceTree.overlays = [
  #   {
  #     name = "gpio";
  #     dtboFile = ./gpio.dtbo;
  #   }
  # ];

  # hardware.rockpi-quad = {
  #   enable = true;
  #   # Optional: Customize settings (see flake.nix for options)
  #   settings = {
  #     # fan.lv0 = 40;
  #     # oled."f-temp" = true;
  #   };
  # };

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

  projectinitiative = {
    services = {
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
                "cargohold:9100"
                "lepotato:9100"
                "stormjib:9100"
                "lighthouse-east:9100"
                "lighthouse-west:9100"
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
                "lighthouse-east:9633"
                "lighthouse-west:9633"
              ];
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
              path_prefix = "/var/lib/loki";
              replication_factor = 1;
              # Defines the storage backend used by all components.
              storage = {
                filesystem = {
                  chunks_directory = "/var/lib/loki/chunks";
                  rules_directory = "/var/lib/loki/rules";
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
                active_index_directory = "/var/lib/loki/index";
                cache_location = "/var/lib/loki/cache";
                cache_ttl = "24h";
                # Note: 'shared_store' is removed; it's now handled by the 'common.storage' block.
              };
            };

            compactor = {
              working_directory = "/var/lib/loki/compactor";
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
