# /path/to/your/nixos/modules/bcachefs-scrub-auto.nix
{ config, lib, pkgs, namespace ? "mySystem", ... }:

with lib;

let
  # Define configuration options under a specific namespace
  cfg = config.${namespace}.services.bcachefsScrubAuto;

  # Helper script to send Telegram messages using curl (Unchanged)
  telegramNotifierScript = pkgs.writeShellScriptBin "bcachefs-scrub-notify" ''
    #!/usr/bin/env bash
    set -euo pipefail # Exit on error, undefined variable, or pipe failure

    TOKEN_PATH="$1"
    CHAT_ID_PATH="$2"
    MESSAGE="$3"

    # --- Basic Input Validation ---
    if [[ ! -f "$TOKEN_PATH" ]]; then
      echo "Error: Telegram token file not found at ''${TOKEN_PATH}" >&2
      exit 1
    fi
    if [[ ! -f "$CHAT_ID_PATH" ]]; then
      echo "Error: Telegram chat ID file not found at ''${CHAT_ID_PATH}" >&2
      exit 1
    fi

    # --- Read Credentials ---
    TELEGRAM_TOKEN=$(cat "''${TOKEN_PATH}")
    TELEGRAM_CHAT_ID=$(cat "''${CHAT_ID_PATH}")

    if [[ -z "$TELEGRAM_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
       echo "Error: Telegram token or chat ID is empty." >&2
       exit 1
    fi

    # --- Escape message for MarkdownV2 ---
    ESCAPED_MESSAGE=$(echo "$MESSAGE" | sed -e 's/\([_*\[\]()~`>#+-=|{}.!\\]\)/\\\1/g')

    # --- Send Message via Curl ---
    echo "Sending Telegram notification..." >&2 # Log action
    ${pkgs.curl}/bin/curl --silent --show-error --fail-with-body \
      -X POST "https://api.telegram.org/bot''${TELEGRAM_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=''${TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=''${ESCAPED_MESSAGE}" \
      --data-urlencode "parse_mode=MarkdownV2"

    CURL_EXIT_CODE=$?
    if [[ $CURL_EXIT_CODE -ne 0 ]]; then
        echo "Error: Failed to send Telegram message (curl exit code: $CURL_EXIT_CODE)." >&2
    else
        echo "Telegram notification sent successfully." >&2
    fi
    exit $CURL_EXIT_CODE
  '';

  # Generate a systemd-safe name from the mount point
  escapeName = name: escapeSystemdPath name;
  scrubUnitName = name: "bcachefs-scrub-${escapeName name}";
  scrubFailureNotifyUnitName = name: "bcachefs-scrub-failure-notify-${escapeName name}";
  scrubTimerUnitName = name: "bcachefs-scrub-${escapeName name}";

  # Get hostname string safely for messages
  hostnameCmd = "${pkgs.hostname}/bin/hostname";

in
{
  options.${namespace}.services.bcachefsScrubAuto = {
     # ... Options remain the same ...
    enable = mkEnableOption "Periodic bcachefs scrub service (auto-detects mounts) with Telegram notifications";

    excludeMountPoints = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "/mnt/bcachefs-no-scrub" ];
      description = ''
        List of exact mount points (as defined in `fileSystems`) to exclude
        from automatic scrubbing.
      '';
    };

    schedule = mkOption {
      type = types.str;
      default = "weekly";
      example = "*-*-1,15 03:00:00";
      description = ''
        When to run the scrubs automatically. Applies to all detected mounts.
        Uses systemd.time OnCalendar= format. Timers include randomized delay.
        See `man systemd.time` for detailed syntax.
      '';
    };

    telegramTokenPath = mkOption {
      type = types.path;
      default = "/run/secrets/telegram-token";
      description = "Absolute path to the file containing the Telegram bot token.";
    };

    telegramChatIdPath = mkOption {
      type = types.path;
      default = "/run/secrets/telegram-chatid";
      description = "Absolute path to the file containing the Telegram chat ID.";
    };

    notifyOnStart = mkOption {
      type = types.bool;
      default = true;
      description = "Send a Telegram notification when a scrub starts.";
    };

    notifyOnSuccess = mkOption {
      type = types.bool;
      default = true;
      description = "Send a Telegram notification when a scrub completes successfully.";
    };

    notifyOnFailure = mkOption {
      type = types.bool;
      default = true;
      description = "Send a Telegram notification if a scrub command fails.";
    };
  };

  # CORRECTED CONFIG SECTION: mkIf applies to the result of the let...in block
  config = mkIf cfg.enable ( # <-- Added opening parenthesis
    # --- Auto-detect bcachefs mounts and generate units ---
    let
      # Filter fileSystems to get only bcachefs types, excluding specified mounts
      bcachefsMounts = lib.attrsets.filterAttrs (name: value:
        value.fsType == "bcachefs" && !(elem name cfg.excludeMountPoints)
      ) config.fileSystems;

      # Generate Systemd Units for each detected mount
      generatedUnits = lib.attrsets.mapAttrs' (mountPoint: fsConfig:
        let
          sName = scrubUnitName mountPoint;
          fName = scrubFailureNotifyUnitName mountPoint;
          tName = scrubTimerUnitName mountPoint;
          startMsg = "🚀 Starting bcachefs scrub on host `${hostnameCmd}` for mount point: ${mountPoint}...";
          successMsg = "✅ Successfully completed bcachefs scrub on host `${hostnameCmd}` for mount point: ${mountPoint}.";
          failMsg = "❌ ERROR: bcachefs scrub failed on host `${hostnameCmd}` for mount point: ${mountPoint}! Check systemd logs: journalctl -u ${sName}.service";
        in
        lib.nameValuePair "systemd" { # Nest generated units under 'systemd' key
          services = {
            # Scrub Service
            "${sName}" = {
              description = "Run bcachefs scrub on ${mountPoint}";
              path = [ pkgs.bcachefs-tools pkgs.curl pkgs.hostname ];
              serviceConfig = {
                Type = "oneshot"; User = "root"; Group = "root";
                ExecStartPre = mkIf cfg.notifyOnStart "+${telegramNotifierScript}/bin/bcachefs-scrub-notify '${cfg.telegramTokenPath}' '${cfg.telegramChatIdPath}' '${startMsg}'";
                ExecStart = "${pkgs.bcachefs-tools}/bin/bcachefs fs scrub ${mountPoint}";
                ExecStartPost = mkIf cfg.notifyOnSuccess "+${telegramNotifierScript}/bin/bcachefs-scrub-notify '${cfg.telegramTokenPath}' '${cfg.telegramChatIdPath}' '${successMsg}'";
                OnFailure = mkIf cfg.notifyOnFailure "${fName}.service";
              };
            };
            # Failure Notification Service
            "${fName}" = mkIf cfg.notifyOnFailure {
              description = "Notify Telegram about bcachefs scrub failure on ${mountPoint}";
              path = [ pkgs.curl pkgs.hostname ];
              serviceConfig = {
                Type = "oneshot"; User = "root";
                ExecStart = "${telegramNotifierScript}/bin/bcachefs-scrub-notify '${cfg.telegramTokenPath}' '${cfg.telegramChatIdPath}' '${failMsg}'";
              };
            };
          }; # End services
          timers = {
            # Timer
            "${tName}" = {
              description = "Timer for Bcachefs Scrub on ${mountPoint}";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = cfg.schedule;
                Unit = "${sName}.service";
                Persistent = true;
                RandomizedDelaySec = "1h";
              };
            };
          }; # End timers
        } # End systemd value for this mount point
      ) bcachefsMounts; # End mapAttrs'

    in # <-- 'in' for the let block

    # --- The attribute set returned by the let...in block ---
    {
      # Merge the generated systemd units into the main config
      systemd = lib.mkMerge (lib.attrsets.attrValues generatedUnits);

      # Secret management comments/assertions can also go here if needed,
      # although defining sops secrets usually happens elsewhere in the config.
    }
  ); # <-- Added closing parenthesis
}
