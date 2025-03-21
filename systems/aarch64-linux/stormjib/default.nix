# the masthead routers will be named accordingly:
# Topsail (Primary) & StormJib (Backup)
#     Topsail: Agile sail for fair-weather speed (primary performance).
#     StormJib: Rugged sail for heavy weather (backup resilience).

{ ... }:
{
  config = {
    projectinitiative = {
      # hosts.masthead.stormjib.enable = true;
      networking = {
        tailscale.enable = true;
      };
    };

    services.openssh.enable = true;

    # Use tmpfs for temporary files
    fileSystems."/tmp" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "nosuid" "nodev" "relatime" "size=256M" ];
    };
  
    # journald settings to reduce writes
    services.journald.extraConfig = ''
      Storage=volatile
      RuntimeMaxUse=64M
      SystemMaxUse=64M
    '';

    disko = {
      devices = {
        disk = {
          sd = {
            type = "disk";
            device = "/dev/mmcblk0";
            content = {
              type = "gpt";
              partitions = {
                # Boot partition - fixed 256MB size
                boot = {
                  name = "boot";
                  size = "256M";  # Fixed size for boot
                  type = "EF00"; # EFI System Partition
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                    mountOptions = [ "defaults" "noatime" ];
                  };
                };
            
                # Root partition - read-only
                root = {
                  name = "root";
                  size = "20%";  # Percentage of remaining space
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/";
                    mountOptions = [ "defaults" "noatime" ];# "ro" ]; # Read-only mount
                  };
                };
            
                # Nix store partition
                nix = {
                  name = "nix";
                  size = "35%";  # Percentage of remaining space
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/nix";
                    mountOptions = [ "defaults" "noatime" ];
                  };
                };
            
                # Logs partition
                logs = {
                  name = "logs";
                  size = "10%";  # Percentage of remaining space
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/var/log";
                    mountOptions = [ "defaults" "noatime" "commit=600" ];
                  };
                };
            
                # Persistent data partition
                data = {
                  name = "data";
                  size = "100%";  # Use all remaining space
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/var/lib";
                    mountOptions = [ "defaults" "noatime" "commit=600" ];
                  };
                };
              };
            };
          };
        };
      };
    };

  };
}
