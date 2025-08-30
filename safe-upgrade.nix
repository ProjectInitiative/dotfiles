# /etc/nixos/modules/safe-upgrade.nix
{ pkgs, ... }:

{
  # Ensure the built-in auto-upgrade functionality is disabled,
  # as this module replaces it entirely.
  system.autoUpgrade.enable = false;

  # --- Custom Safe Upgrade Service ---
  # This systemd service contains the core logic for attempting an upgrade,
  # verifying its success, and rolling back if it fails.
  systemd.services.custom-safe-upgrade = {
    description = "Custom Safe NixOS Upgrade with Health Check";
    
    # This service runs as a one-off task.
    serviceConfig = {
      Type = "oneshot";
    };

    # The full path to necessary command-line tools.
    path = with pkgs; [ coreutils iputils systemd nix ];

    # This is the main script that orchestrates the upgrade process.
    script = ''
      set -e  # Exit immediately if any command fails.

      # Define the location for the lock file. This file prevents the script
      # from running again if a previous upgrade failed and rolled back.
      LOCK_FILE="/var/lib/nixos-upgrade-lock"

      # --- Pre-flight Check ---
      # If the lock file exists, it means a previous upgrade failed.
      # We log this and exit gracefully without trying again.
      # A human operator must remove the file to re-enable upgrades.
      if [ -f "$LOCK_FILE" ]; then
        echo "Lock file found at $LOCK_FILE. Skipping upgrade."
        # Use `logger` to send a message to the system journal for monitoring.
        logger -t safe-upgrade "Upgrade skipped: Lock file exists."
        exit 0
      fi

      # --- 1. Attempt the Upgrade ---
      # This command pulls the latest config from your Git repo and switches to it.
      # It does NOT use '--upgrade'. The source of truth is the flake.lock in the repo.
      # The `||` part ensures that if this command fails, the script exits.
      nixos-rebuild switch --flake "git+ssh://git@github.com/your-org/your-repo#yourHostname" || exit 1

      # --- 2. Verify System Health ---
      # After a successful switch, we wait a moment for services to initialize
      # before running our checks.
      echo "Switch successful. Waiting 15 seconds before health check..."
      sleep 15

      # The health check itself. This is a sequence of commands. If any one of
      # them fails, the entire `if` condition is considered false.
      #
      # Customize these checks to match your machine's critical functions.
      #
      # Check 1: Can we reach the local gateway?
      # Check 2: Can we reach a public DNS server?
      # Check 3: Is our main application's systemd service running?
      if \
        ping -c 3 -W 5 192.168.1.1 && \
        ping -c 3 -W 5 8.8.8.8 && \
        systemctl is-active --quiet my-critical-app.service
      then
        # --- Success Case ---
        echo "Health check passed. Upgrade is complete."
        logger -t safe-upgrade "System successfully upgraded and health check passed."
      else
        # --- Failure Case ---
        echo "Health check FAILED. Rolling back to previous configuration."
        logger -t safe-upgrade "Health check failed. Rolling back and creating lock file."
        
        # --- 3. Roll Back on Failure ---
        # This is the crucial failsafe command. It immediately activates the
        # last known-good configuration.
        nixos-rebuild switch --rollback

        # Create the lock file to prevent future automatic upgrade attempts.
        touch "$LOCK_FILE"
        
        # Exit with a non-zero status code to indicate failure.
        exit 1
      fi
    '';
  };

  # --- Systemd Timer ---
  # This timer triggers the service defined above on a schedule.
  systemd.timers.custom-safe-upgrade = {
    description = "Timer for Custom Safe NixOS Upgrade";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # When to run the upgrade. "daily" runs at midnight.
      # "*-*-* 04:00:00" would run at 4 AM every day.
      OnCalendar = "daily";
      
      # If the machine was off when the timer was supposed to run,
      # run it as soon as the machine boots up.
      Persistent = true;
    };
  };
}

