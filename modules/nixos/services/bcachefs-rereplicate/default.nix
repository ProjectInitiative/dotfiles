{
  config,
  lib,
  pkgs,
  namespace, # Make sure this is passed in correctly when importing
  ...
}:

with lib;
with lib.types;

let
  # Access the final evaluated options from the config object.
  cfg = config.${namespace}.services.bcachefsRereplicateAuto;

  # Helper function to create valid systemd unit names from filesystem paths.
  escapeName = path:
    if path == "/"
    then "-" # Results in unit names like bcachefs-rereplicate--.service
    else lib.replaceStrings ["/"] ["-"] (lib.removePrefix "/" path);

  rereplicateServiceName = mountPoint: "bcachefs-rereplicate-${escapeName mountPoint}";
  rereplicateTimerName = mountPoint: "bcachefs-rereplicate-${escapeName mountPoint}";

in
{
  # Define the configuration options for this module.
  options.${namespace}.services.bcachefsRereplicateAuto = {
    enable = mkEnableOption (mdDoc "Periodic bcachefs rereplicate service");

    targetMountPoints = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "/mnt/bcachefs-main" ];
      description = mdDoc ''
        List of bcachefs mount points to target for rereplication.
        The module will perform a sanity check to ensure these mount points
        are defined in `fileSystems` and are of type `bcachefs`.
      '';
    };
  };

  # The config block defines the actual system configuration based on the options.
  config = mkIf cfg.enable {
    # Assertions to ensure valid configuration.
    assertions =
      [
        {
          assertion = cfg.enable -> (builtins.length cfg.targetMountPoints > 0);
          message = "${namespace}.services.bcachefsRereplicateAuto is enabled but no targetMountPoints are specified.";
        }
      ] ++ map (mountPoint: {
        assertion = builtins.any (fs: fs.fsType == "bcachefs" && fs.mountPoint == mountPoint) (lib.attrValues config.fileSystems);
        message = "${namespace}.services.bcachefsRereplicateAuto: Target mount point \"${mountPoint}\" is not a configured bcachefs filesystem in `fileSystems`.";
      }) cfg.targetMountPoints;

    # Define all systemd services as a single attribute set.
    systemd.services =
      lib.listToAttrs (map (mountPoint:
        let
          sName = rereplicateServiceName mountPoint;
        in
        {
          name = sName; # This becomes the attribute name in the final set
          value = {    # This is the service definition
            description = "Run bcachefs data rereplicate on ${mountPoint}";
            path = [ pkgs.bcachefs-tools ]; # Ensures bcachefs-tools is in PATH
            serviceConfig = {
              Type = "oneshot";
              User = "root";
              Group = "root";
              # Using nice and ionice to reduce the impact on system performance.
              Nice = 19;
              IOSchedulingClass = "idle";
              ExecStart = "${pkgs.bcachefs-tools}/bin/bcachefs data rereplicate ${escapeShellArg mountPoint}";
            };
          };
        }
      ) cfg.targetMountPoints);

    # Define all systemd timers as a single attribute set.
    systemd.timers =
      lib.listToAttrs (map (mountPoint:
        let
          sName = rereplicateServiceName mountPoint; # Service to activate
          tName = rereplicateTimerName mountPoint;  # Timer's own name
        in
        {
          name = tName; # Attribute name for the timer
          value = {   # Timer definition
            description = "Daily timer for bcachefs data rereplicate on ${mountPoint}";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "daily"; # Runs once a day
              Unit = "${sName}.service"; # Explicitly state the service unit to activate
              Persistent = true;      # Run on next boot if a start time was missed
              RandomizedDelaySec = "4h"; # Spread out the load
            };
          };
        }
      ) cfg.targetMountPoints);
  };
}
