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

        bcachefsRereplicateAuto = {
          enable = true;
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

              retention = {
                hourly = 12;
                daily = 14;
                weekly = 8;
                monthly = 12;
                yearly = 5;
              };
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
