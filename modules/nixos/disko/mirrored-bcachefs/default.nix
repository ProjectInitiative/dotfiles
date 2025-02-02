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
  cfg = config.${namespace}.disko.mirrored-bcachefs;
  inherit (lib) mkOption types mkIf listToAttrs;
in
{
  options.${namespace}.disko.mirrored-bcachefs = with types; {
    enable = mkBoolOpt false "Whether or not to enable a mirrored bcachefs boot and root partition";
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
                type = "EF02"; # for grub MBR
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
                  type = "filesystem";
                  format = "bcachefs";
                  extraArgs = [ "--replicas=2" ];
                  mountpoint = "/";
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
      };
    };

    boot = {
      loader.grub = {
        enable = true;
        devices = cfg.mirroredDrives;
        efiSupport = true;
        efiInstallAsRemovable = true;
      };

      initrd = {
        availableKernelModules = [ "bcachefs" "md_mod" "raid1" ];
        kernelModules = [ "bcachefs" "md_mod" ];
      };

      # kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
    };

    fileSystems = let
      rootDevices = lib.concatStringsSep ":" (map (d: "${d}3") cfg.mirroredDrives);
    in mkForce {
      "/" = {
        device = rootDevices;
        fsType = "bcachefs";
      };
      "/boot" = {
        device = "/dev/md/boot";
        fsType = "vfat";
      };
    };

    # services.mdadm.enable = true;
    boot.swraid.mdadmConf = ''
      MAILADDR=nobody@nowhere
    '';

    environment.systemPackages = [ pkgs.bcachefs-tools ];
  };
}
