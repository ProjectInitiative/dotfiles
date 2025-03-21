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
    
    criticalDiskUsage = mkOption {
      type = types.int;
      default = 90;
      description = "Disk usage percentage considered critical";
    };
    
    warningDiskUsage = mkOption {
      type = types.int;
      default = 75;
      description = "Disk usage percentage considered a warning";
    };
    
    detailedReport = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to include detailed information in the report";
    };
  };

  config = mkIf cfg.enable {
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
        gawk
        coreutils
        hostname
        procps
        bc
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

          # Create temporary files for the reports
          SUMMARY_REPORT=$(mktemp)
          DETAILED_REPORT=$(mktemp)
          
          # Get server hostname and date
          HOSTNAME=$(hostname)
          CURRENT_DATE=$(date +"%Y-%m-%d %H:%M")
          
          # Function to get disk status emoji
          get_disk_status() {
            local usage="$1"
            if [ "''${usage}" -ge ${toString cfg.criticalDiskUsage} ]; then
              echo "🔴"
            elif [ "''${usage}" -ge ${toString cfg.warningDiskUsage} ]; then
              echo "🟡"
            else
              echo "🟢"
            fi
          }
          
          # Function to format bytes to human readable
          format_bytes() {
            local bytes="$1"
            if (( "''${bytes}" >= 1073741824 )); then
              echo "$((''${bytes} / 1073741824))GB"
            elif (( "''${bytes}" >= 1048576 )); then
              echo "$((''${bytes} / 1048576))MB"
            elif (( "''${bytes}" >= 1024 )); then
              echo "$((''${bytes} / 1024))KB"
            else
              echo "''${bytes}B"
            fi
          }

          # SUMMARY REPORT
          echo "*SERVER HEALTH SUMMARY*" > "$SUMMARY_REPORT"
          echo "📊 *''${HOSTNAME}* - ''${CURRENT_DATE}" >> "$SUMMARY_REPORT"
          echo "" >> "$SUMMARY_REPORT"

          # System uptime
          UPTIME_INFO=$(uptime -p)
          echo "⏱️ *Uptime:* ''${UPTIME_INFO}" >> "$SUMMARY_REPORT"
          
          # Load average
          LOAD=$(cat /proc/loadavg | cut -d ' ' -f 1-3)
          CPU_COUNT=$(nproc)
          LOAD_1=$(echo "$LOAD" | cut -d ' ' -f 1)
          
          if (( $(echo "''${LOAD_1} > ''${CPU_COUNT} * 0.8" | bc -l) )); then
            LOAD_ICON="🔴"
          elif (( $(echo "''${LOAD_1} > ''${CPU_COUNT} * 0.5" | bc -l) )); then
            LOAD_ICON="🟡"
          else
            LOAD_ICON="🟢"
          fi
          
          echo "''${LOAD_ICON} *Load:* ''${LOAD} ($(nproc) CPU cores)" >> "$SUMMARY_REPORT"
          
          # Memory usage
          MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
          MEM_USED=$(free -m | awk '/^Mem:/{print $3}')
          MEM_PCT=$((''${MEM_USED} * 100 / ''${MEM_TOTAL}))
          
          if [ "''${MEM_PCT}" -ge 90 ]; then
            MEM_ICON="🔴"
          elif [ "''${MEM_PCT}" -ge 75 ]; then
            MEM_ICON="🟡"
          else
            MEM_ICON="🟢"
          fi
          
          echo "''${MEM_ICON} *Memory:* ''${MEM_USED}MB/''${MEM_TOTAL}MB (''${MEM_PCT}%)" >> "$SUMMARY_REPORT"
          
          # Disk usage summary
          echo "💾 *Disk Usage:*" >> "$SUMMARY_REPORT"
          df -h | grep -v "tmpfs\|devtmpfs" | grep -v "^Filesystem" | while read line; do
            FS=$(echo "$line" | awk '{print $1}')
            SIZE=$(echo "$line" | awk '{print $2}')
            USED=$(echo "$line" | awk '{print $3}')
            AVAIL=$(echo "$line" | awk '{print $4}')
            USE_PCT=$(echo "$line" | awk '{print $5}' | tr -d '%')
            MOUNT=$(echo "$line" | awk '{print $6}')
            
            STATUS_EMOJI=$(get_disk_status "''${USE_PCT}")
            echo "''${STATUS_EMOJI} ''${MOUNT}: ''${USED}/''${SIZE} (''${USE_PCT}%)" >> "$SUMMARY_REPORT"
          done
          
          # Top process by CPU
          TOP_CPU=$(ps -eo pid,comm,%cpu --sort=-%cpu | head -n 2 | tail -n 1)
          TOP_CPU_PID=$(echo "$TOP_CPU" | awk '{print $1}')
          TOP_CPU_PROC=$(echo "$TOP_CPU" | awk '{print $2}')
          TOP_CPU_PCT=$(echo "$TOP_CPU" | awk '{print $3}')
          
          echo "🔄 *Top CPU:* ''${TOP_CPU_PROC} (''${TOP_CPU_PCT}%)" >> "$SUMMARY_REPORT"
          
          # SMART data summary
          echo "🔍 *SMART Health:*" >> "$SUMMARY_REPORT"
          DRIVES=$(lsblk -d -o NAME,TYPE | grep disk | awk '{print $1}')
          EXCLUDE_PATTERN="${concatStringsSep "|" cfg.excludeDrives}"
          if [ -n "$EXCLUDE_PATTERN" ]; then
            DRIVES=$(echo "$DRIVES" | grep -v -E "$EXCLUDE_PATTERN" || true)
          fi
          
          if [ -z "$DRIVES" ]; then
            echo "No drives detected for monitoring." >> "$SUMMARY_REPORT"
          else
            for drive in $DRIVES; do
              DRIVE_PATH="/dev/''${drive}"
              # Check drive size
              DRIVE_SIZE=$(lsblk -dn -o SIZE "''${DRIVE_PATH}")
              
              # Check if SMART is available
              if ! smartctl -i "''${DRIVE_PATH}" | grep -q "SMART support is: Available"; then
                echo "- ''${drive} (''${DRIVE_SIZE}): SMART not available" >> "$SUMMARY_REPORT"
              else
                # Get overall health status
                SMART_STATUS=$(smartctl -H "''${DRIVE_PATH}" 2>/dev/null | grep -E "SMART overall-health" | awk '{print $NF}')
                if [ "''${SMART_STATUS}" = "PASSED" ]; then
                  HEALTH_EMOJI="🟢"
                else
                  HEALTH_EMOJI="🔴"
                fi
                
                # Get reallocated sectors (if any)
                REALLOC_SECTORS=$(smartctl -A "''${DRIVE_PATH}" | grep "Reallocated_Sector_Ct" | awk '{print $10}')
                PENDING_SECTORS=$(smartctl -A "''${DRIVE_PATH}" | grep "Current_Pending_Sector" | awk '{print $10}')
                
                # Get temperature (if available)
                TEMP=$(smartctl -A "''${DRIVE_PATH}" | grep "Temperature_Celsius" | awk '{print $10}')
                
                # Format the output
                SMART_INFO="''${HEALTH_EMOJI} ''${drive} (''${DRIVE_SIZE}): "
                if [ -n "''${SMART_STATUS}" ]; then
                  SMART_INFO+="''${SMART_STATUS}"
                fi
                
                if [ -n "''${REALLOC_SECTORS}" ] && [ "''${REALLOC_SECTORS}" -gt 0 ]; then
                  SMART_INFO+=", ''${REALLOC_SECTORS} reallocated sectors"
                fi
                
                if [ -n "''${PENDING_SECTORS}" ] && [ "''${PENDING_SECTORS}" -gt 0 ]; then
                  SMART_INFO+=", ''${PENDING_SECTORS} pending sectors"
                fi
                
                if [ -n "''${TEMP}" ]; then
                  SMART_INFO+=", ''${TEMP}°C"
                fi
                
                echo "''${SMART_INFO}" >> "$SUMMARY_REPORT"
              fi
            done
          fi
          
          # Network traffic summary
          if [ "${toString cfg.enableNetworkMonitoring}" = "1" ]; then
            echo "🌐 *Network:*" >> "$SUMMARY_REPORT"
            # Get primary interface (excluding lo, tailscale)
            PRIMARY_IF=$(ip -o addr show | grep -v -E "lo|tailscale|dummy" | head -n 1 | awk '{print $2}' | tr -d ':')
            if [ -n "''${PRIMARY_IF}" ]; then
              RX_BYTES=$(cat /sys/class/net/"''${PRIMARY_IF}"/statistics/rx_bytes)
              TX_BYTES=$(cat /sys/class/net/"''${PRIMARY_IF}"/statistics/tx_bytes)
              RX_HUMAN=$(format_bytes "''${RX_BYTES}")
              TX_HUMAN=$(format_bytes "''${TX_BYTES}")
              echo "''${PRIMARY_IF}: ↓''${RX_HUMAN} ↑''${TX_HUMAN}" >> "$SUMMARY_REPORT"
            fi
          fi
          
          # DETAILED REPORT
          echo "*SERVER HEALTH REPORT*" > "$DETAILED_REPORT"
          echo "📊 *''${HOSTNAME}* - ''${CURRENT_DATE}" >> "$DETAILED_REPORT"
          echo "" >> "$DETAILED_REPORT"

          # System uptime
          echo "*UPTIME:*" >> "$DETAILED_REPORT"
          uptime >> "$DETAILED_REPORT"
          echo "" >> "$DETAILED_REPORT"

          # Disk usage
          echo "*DISK USAGE:*" >> "$DETAILED_REPORT"
          df -h | grep -v "tmpfs\|devtmpfs" >> "$DETAILED_REPORT"
          echo "" >> "$DETAILED_REPORT"

          # Auto-detect physical drives
          echo "*DRIVE HEALTH (S.M.A.R.T):*" >> "$DETAILED_REPORT"

          # Get all physical drives
          DRIVES=$(lsblk -d -o NAME,TYPE | grep disk | awk '{print $1}')

          # Exclude drives as specified
          EXCLUDE_PATTERN="${concatStringsSep "|" cfg.excludeDrives}"
          if [ -n "$EXCLUDE_PATTERN" ]; then
            DRIVES=$(echo "$DRIVES" | grep -v -E "$EXCLUDE_PATTERN" || true)
          fi

          if [ -z "$DRIVES" ]; then
            echo "No drives detected for monitoring." >> "$DETAILED_REPORT"
            echo "" >> "$DETAILED_REPORT"
          else
            for drive in $DRIVES; do
              DRIVE_PATH="/dev/''${drive}"
              echo "Drive ''${DRIVE_PATH}:" >> "$DETAILED_REPORT"
              
              # Check if SMART is available on this drive
              if ! smartctl -i "''${DRIVE_PATH}" | grep -q "SMART support is: Available"; then
                echo "S.M.A.R.T. not available for ''${DRIVE_PATH}" >> "$DETAILED_REPORT"
              else
                # Get overall health status
                smartctl -H "''${DRIVE_PATH}" >> "$DETAILED_REPORT" 2>&1 || echo "Failed to get S.M.A.R.T. status for ''${DRIVE_PATH}" >> "$DETAILED_REPORT"
                
                # Get important attributes
                smartctl -A "''${DRIVE_PATH}" | grep -E '(Reallocated_Sector_Ct|Current_Pending_Sector|Offline_Uncorrectable|Power_On_Hours|Temperature_Celsius)' >> "$DETAILED_REPORT" 2>&1 || true
              fi
              
              # Add drive info (model, size)
              echo "Drive Info:" >> "$DETAILED_REPORT"
              lsblk -o NAME,SIZE,MODEL "''${DRIVE_PATH}" | grep -v NAME >> "$DETAILED_REPORT"
              
              echo "" >> "$DETAILED_REPORT"
            done
          fi

          ${optionalString cfg.enableCpuMonitoring ''
            # CPU information
            echo "*CPU INFORMATION:*" >> "$DETAILED_REPORT"
            echo "Load Average: $(cat /proc/loadavg | cut -d ' ' -f 1-3)" >> "$DETAILED_REPORT"

            # CPU Temperature if available
            if [ -d /sys/class/thermal/thermal_zone0 ]; then
              echo "CPU Temperature: $(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))°C" >> "$DETAILED_REPORT"
            elif command -v sensors &> /dev/null; then
              echo "CPU Temperature:" >> "$DETAILED_REPORT"
              sensors | grep -i "core\|temp" >> "$DETAILED_REPORT" || true
            fi

            # CPU details
            echo "CPU Details:" >> "$DETAILED_REPORT"
            lscpu | grep -E "Model name|Architecture|CPU\(s\)|Thread\(s\) per core|Core\(s\) per socket|Socket\(s\)" >> "$DETAILED_REPORT"

            echo "" >> "$DETAILED_REPORT"
          ''}

          ${optionalString cfg.enableMemoryMonitoring ''
            # Memory usage
            echo "*MEMORY USAGE:*" >> "$DETAILED_REPORT"
            free -h >> "$DETAILED_REPORT"
            echo "" >> "$DETAILED_REPORT"

            # Swap usage if any
            if [ "$(free | grep -c Swap)" -gt 0 ] && [ "$(free | grep Swap | awk '{print $2}')" -gt 0 ]; then
              echo "*SWAP USAGE:*" >> "$DETAILED_REPORT"
              swapon --show >> "$DETAILED_REPORT"
              echo "" >> "$DETAILED_REPORT"
            fi
          ''}

          ${optionalString cfg.enableNetworkMonitoring ''
            # Network stats
            echo "*NETWORK STATS:*" >> "$DETAILED_REPORT"
            echo "Interfaces:" >> "$DETAILED_REPORT"
            ip -o addr show | grep -v -E "lo|dummy" | awk '{print $2 ": " $4}' >> "$DETAILED_REPORT"
            echo "" >> "$DETAILED_REPORT"

            echo "Traffic Statistics:" >> "$DETAILED_REPORT"
            ip -s link | grep -A 5 -E '^[0-9]+: (eth|en|wl)' >> "$DETAILED_REPORT"
            echo "" >> "$DETAILED_REPORT"
          ''}

          # Top processes by CPU and memory
          echo "*TOP PROCESSES BY CPU:*" >> "$DETAILED_REPORT"
          ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 6 >> "$DETAILED_REPORT"
          echo "" >> "$DETAILED_REPORT"

          echo "*TOP PROCESSES BY MEMORY:*" >> "$DETAILED_REPORT"
          ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n 6 >> "$DETAILED_REPORT"
          echo "" >> "$DETAILED_REPORT"

          # Send the summary report to Telegram
          SUMMARY_MESSAGE=$(cat "$SUMMARY_REPORT")
          
          # Make sure summary doesn't exceed Telegram limit
          if [ ''${#SUMMARY_MESSAGE} -gt 4000 ]; then
            SUMMARY_MESSAGE="''${SUMMARY_MESSAGE:0:3950}...
(Message truncated due to length limits)"
          fi
          
          curl -s -X POST \
            https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage \
            -d chat_id=$TELEGRAM_CHAT_ID \
            -d text="$SUMMARY_MESSAGE" \
            -d parse_mode=Markdown
          
          # Send the detailed report if enabled
          if [ "${toString cfg.detailedReport}" = "1" ]; then
            # Instead of sending one large message, split into logical sections
            
            # Section 1: Introduction and Uptime
            SECTION1=$(cat "$DETAILED_REPORT" | sed -n '1,/^$/p')
            SECTION1+=$(cat "$DETAILED_REPORT" | sed -n '/^*UPTIME:*/,/^$/p')
            
            curl -s -X POST \
              https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage \
              -d chat_id=$TELEGRAM_CHAT_ID \
              -d text="$SECTION1" \
              -d parse_mode=Markdown
            sleep 1
            
            # Section 2: Disk info
            SECTION2="*DISK AND STORAGE INFORMATION:*\n\n"
            SECTION2+=$(cat "$DETAILED_REPORT" | sed -n '/^*DISK USAGE:*/,/^*DRIVE HEALTH/p')
            SECTION2+=$(cat "$DETAILED_REPORT" | sed -n '/^*DRIVE HEALTH/,/CPU INFORMATION/p' | head -n -1)
            
            curl -s -X POST \
              https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage \
              -d chat_id=$TELEGRAM_CHAT_ID \
              -d text="$SECTION2" \
              -d parse_mode=Markdown
            sleep 1
            
            # Section 3: CPU/Memory
            SECTION3="*SYSTEM RESOURCES:*\n\n"
            
            if [ "${toString cfg.enableCpuMonitoring}" = "1" ]; then
              SECTION3+=$(cat "$DETAILED_REPORT" | sed -n '/^*CPU INFORMATION:*/,/MEMORY USAGE/p' | head -n -1)
            fi
            
            if [ "${toString cfg.enableMemoryMonitoring}" = "1" ]; then
              SECTION3+=$(cat "$DETAILED_REPORT" | sed -n '/^*MEMORY USAGE:*/,/NETWORK STATS/p' | head -n -1)
            fi
            
            if [ -n "$SECTION3" ] && [ "$SECTION3" != "*SYSTEM RESOURCES:*\n\n" ]; then
              curl -s -X POST \
                https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage \
                -d chat_id=$TELEGRAM_CHAT_ID \
                -d text="$SECTION3" \
                -d parse_mode=Markdown
              sleep 1
            fi
            
            # Section 4: Network & Processes
            SECTION4="*NETWORK AND PROCESSES:*\n\n"
            
            if [ "${toString cfg.enableNetworkMonitoring}" = "1" ]; then
              SECTION4+=$(cat "$DETAILED_REPORT" | sed -n '/^*NETWORK STATS:*/,/TOP PROCESSES BY CPU/p' | head -n -1)
            fi
            
            SECTION4+=$(cat "$DETAILED_REPORT" | sed -n '/^*TOP PROCESSES BY CPU:*/,/TOP PROCESSES BY MEMORY/p' | head -n -1)
            SECTION4+=$(cat "$DETAILED_REPORT" | sed -n '/^*TOP PROCESSES BY MEMORY:*/,/^$/p')
            
            if [ -n "$SECTION4" ] && [ "$SECTION4" != "*NETWORK AND PROCESSES:*\n\n" ]; then
              curl -s -X POST \
                https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage \
                -d chat_id=$TELEGRAM_CHAT_ID \
                -d text="$SECTION4" \
                -d parse_mode=Markdown
            fi
          fi

          # Clean up
          rm "$SUMMARY_REPORT"
          rm "$DETAILED_REPORT"
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

  };
}
