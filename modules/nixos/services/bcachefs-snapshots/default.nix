# /etc/nixos/modules/bcachefs-snap.nix (or your preferred path)
{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;
with lib.types; # Ensure types is available

let
  cfg = config.${namespace}.services.bcachefsSnapshots;

  defaultSnapshotsSubdirName = ".bcachefs_automated_snapshots"; # Default for module if not set per target
  bcachefsSnapConfFile = "/etc/bcachefs-snap.conf";

  # Helper to generate the INI content for a single target
  generateTargetIni = targetName: targetCfg: ''
    [target.${targetName}]
    enabled = ${boolToString targetCfg.enable}
    parent_subvolume = ${targetCfg.parentSubvolume}
    snapshots_subdir_name = ${targetCfg.snapshotsSubdirName}
    read_only = ${boolToString targetCfg.readOnlySnapshots}
    retention_hourly = ${toString targetCfg.retention.hourly}
    retention_daily = ${toString targetCfg.retention.daily}
    retention_weekly = ${toString targetCfg.retention.weekly}
    retention_monthly = ${toString targetCfg.retention.monthly}
    retention_yearly = ${toString targetCfg.retention.yearly}
  '';

  package = pkgs.${namespace}.bcachefs-snap;

in
{
  options.${namespace}.services.bcachefsSnapshots = {
    enable = mkEnableOption (
      mdDoc "bcachefs automatic snapshotting and pruning service for multiple targets"
    );

    # Global timer configurations, these trigger the script which then processes all targets.
    timers = {
      create = {
        enable = mkEnableOption (mdDoc "master timer for creating snapshots for all enabled targets");
        onCalendar = mkOption {
          type = str;
          default = "hourly";
          example = "*-*-* 0/2:00:00"; # Every 2 hours
          description = mdDoc "Systemd OnCalendar expression for snapshot creation trigger.";
        };
      };
      prune = {
        enable = mkEnableOption (mdDoc "master timer for pruning snapshots for all enabled targets");
        onCalendar = mkOption {
          type = str;
          default = "daily";
          example = "*-*-* 03:30:00"; # Daily at 3:30 AM
          description = mdDoc "Systemd OnCalendar expression for snapshot pruning trigger.";
        };
      };
    };

    # Define multiple snapshot targets
    targets = mkOption {
      type = attrsOf (
        submodule (
          { name, ... }:
          {
            # 'name' here is the attribute name of the target
            options = {
              enable = mkEnableOption (mdDoc "this specific snapshot target") // {
                default = true; # Targets are enabled by default if defined
              };
              parentSubvolume = mkOption {
                type = str;
                example = "/mnt/mybcachefs/data";
                description = mdDoc "Absolute path to the bcachefs parent subvolume for this target.";
              };
              snapshotsSubdirName = mkOption {
                type = str;
                default = defaultSnapshotsSubdirName;
                description = mdDoc "Subdirectory name for snapshots within this target's parentSubvolume.";
              };
              readOnlySnapshots = mkOption {
                type = bool;
                default = true;
                description = mdDoc "Create snapshots as read-only for this target.";
              };
              retention = mkOption {
                type = submodule {
                  options = {
                    hourly = mkOption {
                      type = int;
                      default = 0;
                    };
                    daily = mkOption {
                      type = int;
                      default = 0;
                    };
                    weekly = mkOption {
                      type = int;
                      default = 0;
                    };
                    monthly = mkOption {
                      type = int;
                      default = 0;
                    };
                    yearly = mkOption {
                      type = int;
                      default = 0;
                    };
                  };
                };
                default = { }; # Empty by default, so all retentions are 0 unless specified
                description = mdDoc "Retention policy for this specific target.";
                example = literalExpression ''
                  { hourly = 6; daily = 7; weekly = 4; monthly = 3; yearly = 1; }
                '';
              };
            };
          }
        )
      );
      default = { }; # No targets by default
      description = mdDoc ''
        Configuration for multiple bcachefs snapshot targets.
        Each attribute name under 'targets' defines a unique snapshot job.
      '';
      example = literalExpression ''
        {
          systemRoot = {
            parentSubvolume = "/";
            retention = { daily = 7; weekly = 4; };
          };
          userData = {
            parentSubvolume = "/home";
            snapshotsSubdirName = ".user_snaps";
            readOnlySnapshots = false;
            retention = { hourly = 12; daily = 14; monthly = 6; };
          };
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        # Check each enabled target has a parentSubvolume
        assertion = all (target: !(target.enable && target.parentSubvolume == null)) (
          attrValues cfg.targets
        );
        message = "Each enabled target in ${cfgNamespace}.targets must have 'parentSubvolume' set.";
      }
      {
        # Check if at least one target is defined and enabled if the main service is enabled
        assertion =
          if cfg.enable then
            (builtins.length (attrNames cfg.targets) > 0 && any (t: t.enable) (attrValues cfg.targets))
          else
            true;
        message = "If ${cfgNamespace}.enable is true, at least one target must be defined and enabled in ${cfgNamespace}.targets.";
      }
    ];

    environment.systemPackages = [
      package
    ];

    environment.etc."bcachefs-snap.conf" = {
      text = concatStringsSep "\n\n" (mapAttrsToList generateTargetIni cfg.targets);
    };

    systemd.services = {
      # Single service for creating snapshots, script handles iterating targets
      bcachefs-snap-create = mkIf cfg.timers.create.enable {
        description = "Create bcachefs snapshots for all configured targets";
        after = [ "local-fs.target" ];
        # Consider adding specific mount units if targets are on separate mounts
        # Ensure all parentSubvolumes are mounted before this runs.
        # This might require more complex logic if mount points vary widely.
        path = [ pkgs.bcachefs-tools ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = ''
            ${package}/bin/bcachefs-snap --config ${bcachefsSnapConfFile} create
          '';
        };
      };

      # Single service for pruning snapshots
      bcachefs-snap-prune = mkIf cfg.timers.prune.enable {
        description = "Prune bcachefs snapshots for all configured targets";
        after = [ "local-fs.target" ];
        path = [ pkgs.bcachefs-tools ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = ''
            ${package}/bin/bcachefs-snap --config ${bcachefsSnapConfFile} prune --yes
          '';
        };
      };
    };

    systemd.timers = {
      bcachefs-snap-create = mkIf cfg.timers.create.enable {
        description = "Timer for bcachefs snapshot creation (all targets)";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.timers.create.onCalendar;
          Persistent = true;
          Unit = "bcachefs-snap-create.service";
        };
      };

      bcachefs-snap-prune = mkIf cfg.timers.prune.enable {
        description = "Timer for bcachefs snapshot pruning (all targets)";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.timers.prune.onCalendar;
          Persistent = true;
          Unit = "bcachefs-snap-prune.service";
        };
      };
    };
  };
}
