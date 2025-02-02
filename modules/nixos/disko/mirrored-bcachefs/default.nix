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
      # disks = mkOpt (types.listOf types.str) [ ] "Disks for bcachefs array";
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
      bootPartitions = map (d: "${d}1") drives;
      rootPartitions = map (d: "${d}2") drives;
    in {
      disk = listToAttrs (map (device: {
        name = builtins.baseNameOf device;
        value = {
          inherit device;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              boot = {
                size = "1G";
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
                };
              };
            };
          };
        };
      }) drives);

      mdraid.boot = {
        type = "raid1";
        inherit bootPartitions;
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/boot";
        };
      };
    };

    boot = {
      loader.grub = {
        enable = true;
        version = 2;
        devices = cfg.mirroredDrives;
        mirroredBoots = [{
          path = "/boot";
          devices = cfg.mirroredDrives;
        }];
      };

      initrd = {
        availableKernelModules = [ "bcachefs" "md_mod" "raid1" ];
        kernelModules = [ "bcachefs" "md_mod" ];
      };

      kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
    };

    fileSystems = let
      rootDevices = lib.concatStringsSep ":" (map (d: "${d}2") cfg.mirroredDrives);
    in {
      "/" = {
        device = rootDevices;
        fsType = "bcachefs";
      };
      "/boot" = {
        device = "/dev/md/boot";
        fsType = "ext4";
      };
    };

    services.mdadm.enable = true;
    environment.systemPackages = [ pkgs.bcachefs-tools ];

  };

}
