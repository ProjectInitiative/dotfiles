# usage
# {
#   mynamespace.disko.bcachefs-root = {
#     enable = true;
#     disks = [
#       { device = "/dev/sda"; type = "hdd"; }
#       { device = "/dev/nvme0n1"; type = "nvme"; }
#     ];
#     formatExtraArgs = [
#       "--replica=2"
#       "--compression=zstd"
#     ];
#     mountExtraOptions = [
#       "--foreground_target=ssd"
#       "--promote_target=nvme"
#     ];
#   };
# }
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
  cfg = config.${namespace}.disko.bcachefs-pool;
  inherit (lib)
    mkOption
    types
    mkIf
    listToAttrs
    ;
in
{
  options.${namespace}.disko.bcachefs-pool = with types; {
    enable = mkBoolOpt false "Whether to enable Bcachefs root filesystem";
    devices = lib.mkOption {
      type = types.listOf (types.submodule { });
      default = [ ];
      description = "List of devices and their attributes";
    };
    # devices = mkOption {
    #   type = listOf (submodule {
    #     options = {
    #       device = mkOption {
    #         type = str;
    #         example = "/dev/sda";
    #         description = "Block device path";
    #       };
    #       type = mkOption {
    #         type = enum [ "hdd" "ssd" "nvme" ];
    #         description = "Type of the disk (hdd, ssd, nvme)";
    #       };
    #     };
    #   });
    #   default = [];
    #   description = "List of devices and config to include in the Bcachefs array";
    # };

    mountpoint = mkOption {
      type = str;
      default = "/";
      description = "Mountpoint for the Bcachefs filesystem";
    };

    formatArgs = mkOption {
      type = listOf str;
      default = [ ];
      description = "Additional arguments for mkfs.bcachefs (e.g., --replica)";
    };

    mountExtraOptions = mkOption {
      type = listOf str;
      default = [ ];
      description = "Additional mount options (e.g., --foreground_target)";
    };
  };

  config = mkIf (cfg.enable && cfg.devices != [ ]) {
    disko.devices =
      let
        # Generate labels and device paths in order of cfg.disks
        # labelsAndDevices = imap0 (index: disk:
        #   let
        #     # Count previous disks of the same type
        #     sameTypeCount = length (filter (d: d.type == disk.type)
        #       (take (index + 1) cfg.disks));
        #     label = "${disk.type}.${disk.type}${toString sameTypeCount}";
        #   in {
        #     inherit label;
        #     device = "${disk.device}1";
        #   }
        # ) cfg.disks;

      in
      # Build format arguments and device list
      # builtFormatArgs = concatMap ({ label, ... }: ["--label" label]) labelsAndDevices;
      # bcachefsDevices = map ({ device, ... }: device) labelsAndDevices;
      {
        # disk = listToAttrs (map (disk: {
        #   name = builtins.baseNameOf disk.device;
        #   value = {
        #     inherit (disk) device;
        #     type = "disk";
        #     content = {
        #       type = "gpt";
        #       partitions = {
        #         part1 = {
        #           size = "100%";
        #           content = {
        #             type = "bare";
        #           };
        #         };
        #       };
        #     };
        #   };
        # }) cfg.disks);

        bcachefs = {
          pool = {

            type = "bcachefs";
            devices = cfg.devices;
            formatOptions = cfg.formatArgs;
          };
          content = {
            type = "filesystem";
            format = "bcachefs";
            mountpoint = cfg.mountpoint;
            mountOptions = [ "defaults" ] ++ cfg.mountExtraOptions;
          };
        };
      };

    environment.systemPackages = [ pkgs.bcachefs-tools ];
    boot.initrd.kernelModules = [ "bcachefs" ];
  };
}
