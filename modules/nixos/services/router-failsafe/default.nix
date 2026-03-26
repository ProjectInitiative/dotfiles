{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
  cfg = config.projectinitiative.services.router-failsafe;
in
{
  options.projectinitiative.services.router-failsafe = {
    enable = mkEnableOption "Router Failsafe Mechanism";

    validationChecks = mkOption {
      type = types.listOf types.str;
      default = [
        "ping -c 3 -W 5 192.168.1.1"
        "ping -c 3 -W 5 8.8.8.8"
      ];
      description = "List of bash commands to run to validate system health after upgrade.";
    };

    rollbackDelay = mkOption {
      type = types.int;
      default = 60;
      description = "How long to wait (in seconds) for validation checks before triggering a rollback.";
    };
  };

  config = mkIf cfg.enable {
    # Systemd service for post-upgrade validation and rollback
    # This service is explicitly NOT enabled by default on boot
    # It must be started manually by the deployment script
    systemd.services.router-failsafe-validation = {
      description = "Router configuration validation and failsafe rollback";
      # Remove wantedBy to prevent it from starting on boot or during standard activation

      path = with pkgs; [
        coreutils
        iputils
        systemd
        nixos-rebuild
      ];

      serviceConfig = {
        # Use simple type so the deployment script doesn't block waiting for it to finish
        Type = "simple";
        # We don't want this service to timeout and be killed before it finishes
        TimeoutSec = cfg.rollbackDelay + 60;
      };

      script = ''
        echo "Waiting ${toString cfg.rollbackDelay} seconds before validating configuration..."
        sleep ${toString cfg.rollbackDelay}

        echo "Starting validation checks..."

        # Build the validation command list
        CHECKS_PASSED=true

        ${lib.concatMapStringsSep "\n" (check: ''
          if ! ${check}; then
            echo "Validation check failed: ${check}"
            CHECKS_PASSED=false
          fi
        '') cfg.validationChecks}

        if [ "$CHECKS_PASSED" = true ]; then
          echo "All validation checks passed. Configuration is stable."
          logger -t router-failsafe "System validation passed. Configuration is stable."
        else
          echo "Validation checks failed! Initiating rollback..."
          logger -t router-failsafe "System validation failed. Initiating rollback!"

          # Use a transient systemd unit to perform the rollback so we don't deadlock
          # systemd by running nixos-rebuild switch from within a service
          systemd-run --unit=router-failsafe-rollback --description="Emergency Rollback" \
            nixos-rebuild switch --rollback || echo "Failed to trigger rollback unit!"

          exit 1
        fi
      '';
    };
  };
}
