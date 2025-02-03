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
  cfg = config.${namespace}.disko.bcachefs-root;
  inherit (lib) mkOption types mkIf listToAttrs;
in
{
  options.${namespace}.disko.bcachefs-root = with types; {
    enable = mkBoolOpt false "Whether to enable Bcachefs root filesystem";
    disks = mkOption {
      type = listOf (submodule {
        options = {
          device = mkOption {
            type = str;
            example = "/dev/sda";
            description = "Block device path";
          };
          type = mkOption {
            type = enum [ "hdd" "ssd" "nvme" ];
            description = "Type of the disk (hdd, ssd, nvme)";
          };
        };
      });
      default = [];
      description = "List of disks to include in the Bcachefs array";
    };
    mountpoint = mkOption {
      type = str;
      default = "/";
      description = "Mountpoint for the Bcachefs filesystem";
    };
  };

  config = mkIf (cfg.enable && cfg.disks != []) {
    assertions = [
      {
        assertion = cfg.disks != [];
        message = "At least one disk must be specified for Bcachefs root";
      }
    ];

    disko.devices = let
      # Group disks by type and assign labels
      groupedDisks = builtins.groupBy (d: d.type) cfg.disks;
      labelsAndDevices = lib.concatLists (lib.mapAttrsToList (type: disks:
        lib.imap1 (index: disk: {
          label = "${type}.${type}${toString index}";
          device = "${disk.device}1";
        }) disks
      ) groupedDisks);
      # Build extraArgs for bcachefs including labels
      extraArgs = lib.concatMap ({ label, device }: [ "--label" label device ]) labelsAndDevices;
    in {
      disk = listToAttrs (map (disk: {
        name = builtins.baseNameOf disk.device;
        value = {
          inherit (disk) device;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              part1 = {
                size = "100%";
                content = {
                  type = "bare"; # No format, handled by bcachefs
                };
              };
            };
          };
        };
      }) cfg.disks);

      bcachefs = {
        type = "bcachefs";
        devices = map (d: "${d.device}1") cfg.disks;
        inherit extraArgs;
        content = {
          type = "filesystem";
          format = "bcachefs";
          mountpoint = cfg.mountpoint;
          mountOptions = [ "defaults" ];
        };
      };
    };

    # Ensure bcachefs-tools is available
    environment.systemPackages = [ pkgs.bcachefs-tools ];

    # Required kernel modules
    boot.initrd.kernelModules = [ "bcachefs" ];
  };
}
