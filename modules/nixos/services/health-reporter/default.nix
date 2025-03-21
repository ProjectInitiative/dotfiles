{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;

let
  cfg = config.${namespace}.services.health-reporter;
in
{
  options.${namespace}.services.health-reporter = {
    enable = mkEnableOption "Server health monitoring service";

    telegramTokenPath = mkOption {
      type = types.str;
      default = "/run/secrets/telegram-token";
      description = "Path to the file containing the Telegram bot token";
    };

    telegramChatIdPath = mkOption {
      type = types.str;
      default = "/run/secrets/telegram-chatid";
      description = "Path to the file containing the Telegram chat ID";
    };

    reportTime = mkOption {
      type = types.str;
      default = "06:00";
      description = "Time to send daily report in 24h format (HH:MM)";
    };

    enableCpuMonitoring = mkOption {
      type = types.bool;
      default = true;
      description = "Enable CPU usage and temperature monitoring";
    };

    enableMemoryMonitoring = mkOption {
      type = types.bool;
      default = true;
      description = "Enable memory usage monitoring";
    };

    enableNetworkMonitoring = mkOption {
      type = types.bool;
      default = true;
      description = "Enable network traffic monitoring";
    };

    excludeDrives = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "loop"
        "ram"
        "sr"
      ];
      description = "Patterns to exclude when auto-detecting drives";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      smartmontools
      sysstat
      iproute2
      curl
      jq
      util-linux
      gnugrep
      gnused
    ];

    systemd.services.server-health-monitor = {
      description = "Server Health Monitor";
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        bash
        smartmontools
        sysstat
        iproute2
        curl
        jq
        util-linux
        gnugrep
        gnused
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.writeShellScript "health-check.sh" ''
          #!/usr/bin/env bash
          set -euo pipefail

          # Read the Telegram token from the secrets file
          if [ ! -f "${cfg.telegramTokenPath}" ]; then
            echo "Error: Telegram token file not found at ${cfg.telegramTokenPath}" >&2
            exit 1
          fi
          TELEGRAM_TOKEN=$(cat "${cfg.telegramTokenPath}")

          # Read the Telegram chat ID from the secrets file
          if [ ! -f "${cfg.telegramChatIdPath}" ]; then
            echo "Error: Telegram chat ID file not found at ${cfg.telegramChatIdPath}" >&2
            exit 1
          fi
          TELEGRAM_CHAT_ID=$(cat "${cfg.telegramChatIdPath}")

          # Create a temporary file for the report
          REPORT_FILE=$(mktemp)

          echo "SERVER HEALTH REPORT - $(hostname) - $(date)" > $REPORT_FILE
          echo "----------------------------------------" >> $REPORT_FILE

          # System uptime
          echo "UPTIME:" >> $REPORT_FILE
          uptime >> $REPORT_FILE
          echo "" >> $REPORT_FILE

          # Disk usage
          echo "DISK USAGE:" >> $REPORT_FILE
          df -h | grep -v "tmpfs\|devtmpfs" >> $REPORT_FILE
          echo "" >> $REPORT_FILE

          # Auto-detect physical drives
          echo "DRIVE HEALTH (S.M.A.R.T):" >> $REPORT_FILE

          # Get all physical drives
          DRIVES=$(lsblk -d -o NAME,TYPE | grep disk | awk '{print $1}')

          # Exclude drives as specified
          EXCLUDE_PATTERN="${concatStringsSep "|" cfg.excludeDrives}"
          if [ -n "$EXCLUDE_PATTERN" ]; then
            DRIVES=$(echo "$DRIVES" | grep -v -E "$EXCLUDE_PATTERN" || true)
          fi

          if [ -z "$DRIVES" ]; then
            echo "No drives detected for monitoring." >> $REPORT_FILE
            echo "" >> $REPORT_FILE
          else
            for drive in $DRIVES; do
              DRIVE_PATH="/dev/$drive"
              echo "Drive $DRIVE_PATH:" >> $REPORT_FILE
              
              # Check if SMART is available on this drive
              if ! smartctl -i $DRIVE_PATH | grep -q "SMART support is: Available"; then
                echo "S.M.A.R.T. not available for $DRIVE_PATH" >> $REPORT_FILE
              else
                # Get overall health status
                smartctl -H $DRIVE_PATH >> $REPORT_FILE 2>&1 || echo "Failed to get S.M.A.R.T. status for $DRIVE_PATH" >> $REPORT_FILE
                
                # Get important attributes
                smartctl -A $DRIVE_PATH | grep -E '(Reallocated_Sector_Ct|Current_Pending_Sector|Offline_Uncorrectable|Power_On_Hours|Temperature_Celsius)' >> $REPORT_FILE 2>&1 || true
              fi
              
              # Add drive info (model, size)
              echo "Drive Info:" >> $REPORT_FILE
              lsblk -o NAME,SIZE,MODEL $DRIVE_PATH | grep -v NAME >> $REPORT_FILE
              
              echo "" >> $REPORT_FILE
            done
          fi

          ${optionalString cfg.enableCpuMonitoring ''
            # CPU information
            echo "CPU INFORMATION:" >> $REPORT_FILE
            echo "Load Average: $(cat /proc/loadavg | cut -d ' ' -f 1-3)" >> $REPORT_FILE

            # CPU Temperature if available
            if [ -d /sys/class/thermal/thermal_zone0 ]; then
              echo "CPU Temperature: $(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))°C" >> $REPORT_FILE
            elif command -v sensors &> /dev/null; then
              echo "CPU Temperature:" >> $REPORT_FILE
              sensors | grep -i "core\|temp" >> $REPORT_FILE || true
            fi

            # CPU details
            echo "CPU Details:" >> $REPORT_FILE
            lscpu | grep -E "Model name|Architecture|CPU\(s\)|Thread\(s\) per core|Core\(s\) per socket|Socket\(s\)" >> $REPORT_FILE

            echo "" >> $REPORT_FILE
          ''}

          ${optionalString cfg.enableMemoryMonitoring ''
            # Memory usage
            echo "MEMORY USAGE:" >> $REPORT_FILE
            free -h >> $REPORT_FILE
            echo "" >> $REPORT_FILE

            # Swap usage if any
            if [ "$(free | grep -c Swap)" -gt 0 ] && [ "$(free | grep Swap | awk '{print $2}')" -gt 0 ]; then
              echo "SWAP USAGE:" >> $REPORT_FILE
              swapon --show >> $REPORT_FILE
              echo "" >> $REPORT_FILE
            fi
          ''}

          ${optionalString cfg.enableNetworkMonitoring ''
            # Network stats
            echo "NETWORK STATS:" >> $REPORT_FILE
            echo "Interfaces:" >> $REPORT_FILE
            ip -o addr show | grep -v -E "lo|dummy" | awk '{print $2 ": " $4}' >> $REPORT_FILE
            echo "" >> $REPORT_FILE

            echo "Traffic Statistics:" >> $REPORT_FILE
            ip -s link | grep -A 5 -E '^[0-9]+: (eth|en|wl)' >> $REPORT_FILE
            echo "" >> $REPORT_FILE
          ''}

          # Top processes by CPU and memory
          echo "TOP PROCESSES BY CPU:" >> $REPORT_FILE
          ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 6 >> $REPORT_FILE
          echo "" >> $REPORT_FILE

          echo "TOP PROCESSES BY MEMORY:" >> $REPORT_FILE
          ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n 6 >> $REPORT_FILE
          echo "" >> $REPORT_FILE

          # Send the report to Telegram
          MESSAGE=$(cat $REPORT_FILE)

          # Telegram has message length limits, so we might need to split the message
          MAX_LENGTH=4000

          if [ ''${#MESSAGE} -gt $MAX_LENGTH ]; then
            # Split the message into chunks
            while [ ''${#MESSAGE} -gt 0 ]; do
              if [ ''${#MESSAGE} -gt $MAX_LENGTH ]; then
                CHUNK=''${MESSAGE:0:$MAX_LENGTH}
                MESSAGE=''${MESSAGE:$MAX_LENGTH}
              else
                CHUNK=$MESSAGE
                MESSAGE=""
              fi
              
              curl -s -X POST \
                https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage \
                -d chat_id=$TELEGRAM_CHAT_ID \
                -d text="$CHUNK" \
                -d parse_mode=Markdown
              
              # Add a small delay between messages
              sleep 1
            done
          else
            # Send as a single message
            curl -s -X POST \
              https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage \
              -d chat_id=$TELEGRAM_CHAT_ID \
              -d text="$MESSAGE" \
              -d parse_mode=Markdown
          fi

          # Clean up
          rm $REPORT_FILE
        ''}";
        User = "root";
        # Add necessary permissions to read the secrets files
        SupplementaryGroups = optional (
          (hasPrefix "/run/secrets/" cfg.telegramTokenPath)
          || (hasPrefix "/run/secrets/" cfg.telegramChatIdPath)
        ) "keys";
      };
    };

    # This service will need access to the secrets
    systemd.services.server-health-monitor.serviceConfig = {
      # Ensure the service can read the secrets files
      LoadCredential =
        (optional (hasPrefix "/run/secrets/" cfg.telegramTokenPath) "telegram-token:${cfg.telegramTokenPath}")
        ++ (optional (hasPrefix "/run/secrets/" cfg.telegramChatIdPath) "telegram-chatid:${cfg.telegramChatIdPath}");
    };

    # Schedule daily execution
    systemd.timers.server-health-monitor = {
      description = "Timer for Server Health Monitor";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* ${cfg.reportTime}:00";
        Unit = "server-health-monitor.service";
        Persistent = true;
      };
    };

    # Make sure the service depends on the secrets being available
    systemd.services.server-health-monitor.after = optional (
      (hasPrefix "/run/secrets/" cfg.telegramTokenPath)
      || (hasPrefix "/run/secrets/" cfg.telegramChatIdPath)
    ) "sops-nix.service";

    systemd.services.server-health-monitor.requires = optional (
      (hasPrefix "/run/secrets/" cfg.telegramTokenPath)
      || (hasPrefix "/run/secrets/" cfg.telegramChatIdPath)
    ) "sops-nix.service";
  };
}
