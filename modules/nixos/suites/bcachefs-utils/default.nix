{
  options,
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.suites.bcachefs-utils;
in
{
  options.${namespace}.suites.bcachefs-utils = with types; {
    enable = mkBoolOpt false "Whether or not to enable common terminal-env configuration.";

    parentSubvolume = mkOption {
      type = str;
      example = "/mnt/mybcachefs/data";
      description = mdDoc "Absolute path to the bcachefs parent subvolume for this target.";
    };

    retention = mkOption {
      type = submodule {
        options = {
          hourly = mkOption { type = int; default = 12; };
          daily = mkOption { type = int; default = 14; };
          weekly = mkOption { type = int; default = 8; };
          monthly = mkOption { type = int; default = 12; };
          yearly = mkOption { type = int; default = 5; };
        };
      };
      default = { };
      description = mdDoc "Retention policy for snapshots. Each period's value indicates how many snapshots to keep.";
    };
  };

  config = mkIf cfg.enable {

    ${namespace} = {

      services = {
        bcachefsScrubAuto = {
          enable = true;
          targetMountPoints = [
            cfg.parentSubvolume # MANDATORY: Set your actual subvolume path
          ];
          schedule = "*-*-01,15 00:00:00 America/Chicago";
          randomizedDelaySec = "1w";
        };

        # this is handled automatically now
        bcachefsRereplicateAuto = {
          enable = false;
          targetMountPoints = [
            cfg.parentSubvolume # MANDATORY: Set your actual subvolume path
          ];
        };

        bcachefsSnapshots = {
          enable = true;

          timers = {
            create = {
              enable = true;
              onCalendar = "hourly";
            };
            prune = {
              enable = true;
              onCalendar = "daily"; # e.g., "*-*-* 03:15:00"
            };
          };

          targets = {
            mount = {

              parentSubvolume = cfg.parentSubvolume; # MANDATORY: Set your actual subvolume path
              readOnlySnapshots = true; # Optional: default is true

              retention = cfg.retention;
            };

          };
        };

      };

    };

    environment.systemPackages = with pkgs; [
      bcachefs-tools
      pkgs.${namespace}.bcachefs-doctor
      pkgs.${namespace}.bcachefs-fua-test
      pkgs.${namespace}.bcachefs-io-metrics
      pkgs.${namespace}.bcachefs-update-refs
      pkgs.${namespace}.fio-overview
    ];

  };
}
