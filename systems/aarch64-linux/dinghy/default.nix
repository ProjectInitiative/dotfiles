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
  # hostSSHFile = pkgs.writeText "ssh_host_ed25519_key" config.sensitiveNotSecret.dinghy_private_ssh_key;
  # hostSSHPubFile = pkgs.writeText "ssh_host_ed25519_key.pub" config.sensitiveNotSecret.dinghy_public_ssh_key;
  # 1. Define the serial number extraction script
  serialScript = pkgs.writeShellScript "serial.sh" ''
    #!/bin/bash
    # Read the full serial number from the drive identified by its kernel name ($1)
    ${pkgs.hdparm}/sbin/hdparm -I /dev/"$1" | grep 'Serial Number' | awk '{print $3}'
  '';
in
{

  imports = with inputs.nixos-hardware.nixosModules; [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];

  # ============================================================================
  # 1. Image Generation (Minimal)
  # ============================================================================
  sdImage = {
    compressImage = false;
    imageBaseName = "dinghy-rpi4-pure";
    
    # We still provide a basic config.txt to boot U-Boot, 
    # but we assume the detailed overlays might be ignored by the EEPROM.
    populateFirmwareCommands = let
      configTxt = pkgs.writeText "config.txt" ''
        [pi4]
        kernel=u-boot-rpi4.bin
        enable_uart=1
        arm_64bit=1
        avoid_warnings=1
      '';
      in lib.mkForce ''
        cp ${pkgs.raspberrypi-armstubs}/armstub8-gic.bin firmware/
        cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bcm2711-rpi-4-b.dtb firmware/
        cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bootcode.bin firmware/
        cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/fixup4.dat firmware/
        cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/start4.elf firmware/
        cp ${pkgs.ubootRaspberryPi4_64bit}/u-boot.bin firmware/u-boot-rpi4.bin
        cp ${configTxt} firmware/config.txt
      '';
  };

  # ============================================================================
  # 2. Kernel & Hardware (The "Pure Linux" Logic)
  # ============================================================================

  # Use Mainline Kernel (Documentation confirms this is well-supported now)
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

  # Explicitly load the RPi4 Device Tree
  hardware.deviceTree = {
    enable = true;
    name = "broadcom/bcm2711-rpi-4-b.dtb";
    
    # --- FAN CONTROL (NixOS-Managed Overlay) ---
    # Since config.txt is unreliable, we compile a custom overlay to enable 
    # the PWM fan on Pin 13 (PWM1) and apply it at OS boot time.
    overlays = [
      {
        name = "pwm-fan-control";
        dtsText = ''
          /dts-v1/;
          /plugin/;
          / {
            compatible = "brcm,bcm2711";
            fragment@0 {
              target = <&pwm1>;
              __overlay__ {
                status = "okay";
                pinctrl-names = "default";
                pinctrl-0 = <&pwm1_pins>;
              };
            };
            fragment@1 {
              target = <&gpio>;
              __overlay__ {
                pwm1_pins: pwm1_pins {
                  brcm,pins = <13>;
                  brcm,function = <4>; /* Alt0 = PWM1 */
                  brcm,pull = <0>;
                };
              };
            };
          };
        '';
      }
    ];
  };

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  hardware.enableAllHardware = lib.mkForce false;

  # --- KERNEL PARAMETERS & BLACKLISTS ---
  # This is where we kill the interfering hardware without needing config.txt
  hardware.bluetooth.enable = false;
  boot.blacklistedKernelModules = [ 
    "btusb" "btrtl" "btbcm" "btintel" "bluetooth" # Kill BT
    "snd_bcm2835"                                 # Kill Audio (Free up PWM pins)
  ];

  boot.kernelParams = [
    # 1. DISABLE UAS (Critical Stability Fix)
    # The JMicron bridge cannot handle UAS with bcachefs. Force Bulk-Only.
    # "usb-storage.quirks=152d:0561:u,1058:0a10:u"

    # 2. MEMORY STABILITY
    # "swiotlb=65536" # Fix DMA buffer exhaustion on Mainline

    # 3. HARDWARE MASKING (Aggressive)
    # Tell the kernel these devices don't exist to prevent reset loops
    # "bcm2835_dma.fake_channels=0x1f00" # Mask BT DMA channels
    
    # 4. GENERAL STABILITY
    # "pcie_aspm=off"
    # "usb-storage.delay_use=10"
    # "usbcore.autosuspend=-1"
    # "dwc_otg.lpm_enable=0"
    "console=ttyS0,115200n8"
    "console=tty1"
  ];

  # --- UDEV RULES ---
  # services.udev.extraRules = ''
  #   # Serial Number Logic
  #   KERNEL=="sd*", ATTRS{idVendor}=="1058", ATTRS{idProduct}=="0a10", SUBSYSTEMS=="usb", \
  #   PROGRAM="${serialScript} %k", ENV{ID_SERIAL}="USB-%c", ENV{ID_SERIAL_SHORT}="%c"

  #   # I/O Throttling (Safety Net for the JMicron Bridge)
  #   ACTION=="add|change", KERNEL=="sd[a-z]", ATTRS{idVendor}=="1058", ATTRS{idProduct}=="0a10", \
  #   ATTR{queue/max_sectors_kb}="64"
    
  #   # Auto-Export Fan Control (Since we enabled it via Overlay above)
  #   KERNEL=="pwmchip0", SUBSYSTEM=="pwm", ACTION=="add", PROGRAM="/bin/sh -c 'echo 1 > /sys/class/pwm/pwmchip0/export'"
  #   KERNEL=="pwmchip0", SUBSYSTEM=="pwm", ACTION=="add", RUN+="/bin/sh -c 'chown -R root:gpio /sys/class/pwm/pwmchip0/pwm1 && chmod -R g+w /sys/class/pwm/pwmchip0/pwm1'"
  # '';

  boot.supportedFilesystems = lib.mkForce [ "ext4" "vfat" "bcachefs" ];
  boot.kernelModules = [ "bcachefs" ];

  hardware.rockpi-quad = {
    enable = true;
    # Optional: Customize settings (see flake.nix for options)
    settings = {
      fan.lv0 = 40;
      oled."f-temp" = false;
    };
  };

  # environment.etc = {
  #   "ssh/ssh_host_ed25519_key" = {
  #     source = hostSSHFile;
  #     mode = "0600";
  #     user = "root";
  #     group = "root";
  #   };

  #   "ssh/ssh_host_ed25519_key.pub" = {
  #     source = hostSSHPubFile;
  #     mode = "0644";
  #     user = "root";
  #     group = "root";
  #   };
  # };

  
  # doesn't support -E 
  security.sudo-rs.enable = lib.mkForce false;

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
      loft = {
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
                # "172.16.1.51:9100"
                # "172.16.1.52:9100"
                # "172.16.1.53:9100"
                "capstan1:9100"
                "capstan2:9100"
                "capstan3:9100"
                "172.16.1.1:9100"
                "wharfmaster:9100"
                "stormjib:9100"
                "lightship-atx:9100"
                "lightship-dal:9100"
                "lightship-dfw:9100"
                "lighthouse-yul-1:9100"
                "lighthouse-den-1:9100"
              ];
            };
            garage = {
              targets = [
                # "172.16.1.51:31630"
                # "172.16.1.52:31630"
                # "172.16.1.53:31630"
                "capstan1:31630"
                "capstan2:31630"
                "capstan3:31630"
              ];
            };
            # A job for scraping smartctl data if it's on a different port/host
            smart-devices = {
              targets = [
                "127.0.0.1:9633"
                # "172.16.1.51:9633"
                # "172.16.1.52:9633"
                # "172.16.1.53:9633"
                "capstan1:9633"
                "capstan2:9633"
                "capstan3:9633"
                "cargohold:9633"
              ];
            };
            speedtest = {
              targets = [ "172.16.1.1:9469" ];
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
        # TODO: change port from 9095, conflicts with loki
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
    hdparm
    mdadm
    bcachefs-tools
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

  # --- Late-boot bcachefs Mount ---

  # This service runs late in the boot process to mount the bcachefs pool.
  systemd.services.storage-mount = {
    description = "Mount the bcachefs storage pool";

    # Run after the main system is up and running.
    after = [ "rockpi-quad.service" ];
    # Be part of the local filesystem setup target.
    wantedBy = [ "local-fs.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      ExecStart = pkgs.writeShellScript "mount-storage" ''
        set -e
        echo "Waiting for storage devices to appear..."
        DEVICES_TO_WAIT_FOR=("/dev/sda" "/dev/sdb" "/dev/sdc" "/dev/sdd")
        TIMEOUT=30
        for i in $(seq $TIMEOUT); do
          # Check if all devices exist as block devices
          if [ -b "''${DEVICES_TO_WAIT_FOR[0]}" ] && \
             [ -b "''${DEVICES_TO_WAIT_FOR[1]}" ] && \
             [ -b "''${DEVICES_TO_WAIT_FOR[2]}" ] && \
             [ -b "''${DEVICES_TO_WAIT_FOR[3]}" ]; then
            echo "All storage devices found."
            break
          fi

          # If we hit the timeout, exit with an error
          if [ $i -eq $TIMEOUT ]; then
            echo "Error: Timed out waiting for storage devices." >&2
            exit 1
          fi
          sleep 1
        done

        echo "Mounting bcachefs filesystem to ${storageMountPoint}..."
        ${pkgs.coreutils}/bin/mkdir -p ${storageMountPoint}
        ${pkgs.util-linux}/bin/mount -t bcachefs UUID=27cac550-3836-765c-d107-51d27ab4a6e1 ${storageMountPoint}
        echo "Storage mounted."
      '';

      ExecStop = pkgs.writeShellScript "unmount-storage" ''
        set -e
        echo "Unmounting ${storageMountPoint}..."
        ${pkgs.util-linux}/bin/umount -l ${storageMountPoint}
        echo "Storage unmounted."
      '';
    };
  };

  # --- Late-boot MDADM RAID Assembly and Mount ---

  # This service runs late in the boot process, after the system is up.
  # It assembles the RAID array and then mounts it.
  # systemd.services.storage-mount = {
  #   description = "Assemble and mount the storage RAID array";

  #   # Run after the main system is up and running.
  #   after = [ "rockpi-quad.service" ];
  #   # Be part of the local filesystem setup target.
  #   wantedBy = [ "local-fs.target" ];

  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;

  #     # Using 'writeShellScript' allows us to run multiple commands safely.
  #     # `set -e` ensures the script exits immediately if any command fails.
  #     ExecStart = pkgs.writeShellScript "mount-storage" ''
  #       set -e
  #       echo "Waiting for RAID devices to appear..."
  #       DEVICES_TO_WAIT_FOR=("/dev/sda" "/dev/sdb" "/dev/sdc" "/dev/sdd")
  #       TIMEOUT=30
  #       for i in $(seq $TIMEOUT); do
  #         # Check if all devices exist as block devices
  #         if [ -b "''${DEVICES_TO_WAIT_FOR[0]}" ] && \
  #            [ -b "''${DEVICES_TO_WAIT_FOR[1]}" ] && \
  #            [ -b "''${DEVICES_TO_WAIT_FOR[2]}" ] && \
  #            [ -b "''${DEVICES_TO_WAIT_FOR[3]}" ]; then
  #           echo "All RAID devices found."
  #           break
  #         fi

  #         # If we hit the timeout, exit with an error
  #         if [ $i -eq $TIMEOUT ]; then
  #           echo "Error: Timed out waiting for RAID devices." >&2
  #           exit 1
  #         fi
  #         sleep 1
  #       done
  #       echo "Assembling RAID array /dev/md0..."
  #       # Use the explicit command to assemble the array from specific devices
  #       ${pkgs.mdadm}/bin/mdadm --assemble --run --verbose /dev/md0 /dev/sda /dev/sdb /dev/sdc /dev/sdd --force

  #       echo "Mounting /dev/md0 to ${storageMountPoint}..."
  #       ${pkgs.coreutils}/bin/mkdir -p ${storageMountPoint}
  #       ${pkgs.util-linux}/bin/mount /dev/md0 ${storageMountPoint}
  #       echo "Storage mounted."
  #     '';

  #     # Defines how to unmount and stop the array when the service is stopped.
  #     ExecStop = pkgs.writeShellScript "unmount-storage" ''
  #       set -e
  #       echo "Unmounting ${storageMountPoint}..."
  #       ${pkgs.util-linux}/bin/umount -l ${storageMountPoint}

  #       echo "Stopping RAID array /dev/md0..."
  #       ${pkgs.mdadm}/bin/mdadm --stop /dev/md0
  #       echo "Storage stopped."
  #     '';
  #   };
  # };

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
