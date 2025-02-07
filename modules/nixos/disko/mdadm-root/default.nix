{
  options,
  config,
  pkgs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.disko.mdadm-root;
  inherit (lib) mkOption types mkIf listToAttrs;
in
{
  options.${namespace}.disko.mdadm-root = with types; {
    enable = mkBoolOpt false "Whether or not to enable a mirrored mdadm boot and root partition";
    mirroredDrives = mkOption {
      type = types.listOf types.str;
      example = [ "/dev/sda" "/dev/sdb" ];
      description = "List of two block devices to use for mirroring";
    };
  };

  config = mkIf (cfg.enable && cfg.mirroredDrives != []) {
    assertions = [
      {
        assertion = builtins.length cfg.mirroredDrives == 2;
        message = "Must specify exactly two drives for mirroring";
      }
    ];
    disko.devices = let
      drives = cfg.mirroredDrives;
    in {
      disk = listToAttrs (map (device: {
        name = builtins.baseNameOf device;
        value = {
          inherit device;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              BOOT = {
                size = "1M";
                type = "EF02"; # GRUB MBR partition
              };
              ESP = {
                size = "500M";
                type = "EF00";
                content = {
                  type = "mdraid";
                  name = "boot";
                };
              };
              root = {
                size = "100%";
                content = {
                  type = "mdraid";
                  name = "root";
                };
              };
            };
          };
        };
      }) drives);

      mdadm = {
        boot = {
          type = "mdadm";
          level = 1;
          metadata = "1.0";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          type = "mdadm";
          level = 1;
          content = {
            type = "gpt";
            partitions = {
              primary = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
          };
        };
      };
    };

    boot = {
      loader.grub = {
        enable = true;
        devices = cfg.mirroredDrives;
        # mirroredBoots = cfg.mirroredDrives;
        efiSupport = true;
        efiInstallAsRemovable = true;
      };

      initrd = {
        availableKernelModules = [ "md_mod" "raid1" "ext4" ];
        kernelModules = [ "md_mod" ];
      };
    };

    # services.mdadm.enable = true;
    # boot.swraid.mdadmConf = ''
    #   MAILADDR=nobody@nowhere
    # '';

    # Override mdmonitor to log to syslog instead of emailing or alerting
    systemd.services."mdmonitor".environment = {
      MDADM_MONITOR_ARGS = "--scan --syslog";
    };

    environment.systemPackages = [ pkgs.mdadm ];
  };

}
