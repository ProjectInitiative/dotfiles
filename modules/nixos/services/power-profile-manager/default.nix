{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;
with lib.${namespace};

let
  cfg = config.${namespace}.services.power-profile-manager;
in
{
  options.${namespace}.services.power-profile-manager = {
    enable = mkEnableOption "GNOME Power Profile Manager Service";
  };

  config = mkIf cfg.enable {
    systemd.user.services.power-profile-manager = {
      description = "GNOME Power Profile Manager";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.writeShellScriptBin "power-profile-manager" ''
                  #!/usr/bin/env bash

          # Initialize in-memory variables for tracking previous state
          PREV_ON_AC="unknown"
          PREV_LOW_BATTERY="unknown"

          # Function to get current power profile
          get_current_profile() {
            ${pkgs.power-profiles-daemon}/bin/powerprofilesctl get
          }

          # Function to set power profile
          set_profile() {
            ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set "$1"
            echo "Switched to $1 profile"
          }

          # Function to get battery percentage
          get_battery_percentage() {
            local percentage=$(${pkgs.acpi}/bin/acpi | grep -o "[0-9]*%" | tr -d '%')
            if [ -z "$percentage" ]; then
              # Default to 100 if we can't determine the battery percentage
              percentage=100
            fi
            echo "$percentage"
          }

          echo "Starting power profile manager..."
          echo "Initial power profile: $(get_current_profile)"

          while true; do
            # Check if system is on AC power
            if ${pkgs.acpi}/bin/acpi -a | grep -q "on-line"; then
              CURRENT_ON_AC="true"
            else
              CURRENT_ON_AC="false"
            fi

            # Get battery percentage
            BATTERY_PERCENTAGE=$(get_battery_percentage)
            if [ "$BATTERY_PERCENTAGE" -le 40 ]; then
              CURRENT_LOW_BATTERY="true"
            else
              CURRENT_LOW_BATTERY="false"
            fi

            # Determine if power state changed
            AC_STATE_CHANGED="false"
            if [ "$PREV_ON_AC" = "unknown" ] || [ "$CURRENT_ON_AC" != "$PREV_ON_AC" ]; then
              AC_STATE_CHANGED="true"
            fi

            # Determine if battery threshold crossed
            BATTERY_THRESHOLD_CROSSED="false"
            if [ "$PREV_LOW_BATTERY" = "unknown" ] || [ "$CURRENT_LOW_BATTERY" != "$PREV_LOW_BATTERY" ]; then
              BATTERY_THRESHOLD_CROSSED="true"
            fi

            # Set profile based on current state and whether state changed
            if [ "$AC_STATE_CHANGED" = "true" ] || [ "$BATTERY_THRESHOLD_CROSSED" = "true" ]; then
              if [ "$CURRENT_ON_AC" = "true" ]; then
                # AC power - use performance
                echo "AC power detected. Setting performance profile."
                set_profile "performance"
              else
                # Battery power - use balanced or power-saver based on level
                if [ "$CURRENT_LOW_BATTERY" = "true" ]; then
                  echo "Battery below 40%. Setting power-saver profile."
                  set_profile "power-saver"
                else
                  echo "Battery above 40%. Setting balanced profile."
                  set_profile "balanced"
                fi
              fi
            fi

            # Update previous state for next iteration
            PREV_ON_AC="$CURRENT_ON_AC"
            PREV_LOW_BATTERY="$CURRENT_LOW_BATTERY"

            # Sleep for 10 seconds before checking again
            sleep 10
          done
        ''}/bin/power-profile-manager";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Add powerprofilesctl package
    environment.systemPackages = with pkgs; [
      power-profiles-daemon
      acpi
    ];

    # Enable power-profiles-daemon service
    services.power-profiles-daemon.enable = true;
  };
}
