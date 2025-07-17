# /path/to/your/nixos/modules/bcachefs-scrub-auto.nix
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
  # cfg needs to access the final evaluated options from the config object.
  # This line is where the recursion happens if the module's own 'config'
  # block isn't structured carefully.
  cfg = config.${namespace}.services.bcachefsScrubAuto;

  # Helper script to send Telegram messages (no changes needed here)
  telegramNotifierScript = pkgs.writeShellScriptBin "bcachefs-scrub-notify" ''
    #!${pkgs.stdenv.shell}
    set -euo pipefail

    TOKEN_PATH="$1"
    CHAT_ID_PATH="$2"
    MESSAGE_TEMPLATE="$3"

    if [[ ! -f "$TOKEN_PATH" ]]; then
      echo "Error: Telegram token file not found at $TOKEN_PATH" >&2
      exit 1
    fi
    if [[ ! -f "$CHAT_ID_PATH" ]]; then
      echo "Error: Telegram chat ID file not found at $CHAT_ID_PATH" >&2
      exit 1
    fi

    TELEGRAM_TOKEN=$(cat "$TOKEN_PATH")
    TELEGRAM_CHAT_ID=$(cat "$CHAT_ID_PATH")

    if [[ -z "$TELEGRAM_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        echo "Error: Telegram token or chat ID is empty." >&2
        exit 1
    fi

    ACTUAL_HOSTNAME=$(${pkgs.hostname}/bin/hostname)
    MESSAGE_WITH_HOSTNAME=$(echo "$MESSAGE_TEMPLATE" | ${pkgs.gnused}/bin/sed "s%__HOSTNAME__%$ACTUAL_HOSTNAME%g")
    ESCAPED_MESSAGE=$(${pkgs.gnused}/bin/sed -e 's/\([_*\[\]()~`>#+-=|{}.!\\]\)/\\\1/g' <<< "$MESSAGE_WITH_HOSTNAME")

    echo "Sending Telegram notification for host $ACTUAL_HOSTNAME..." >&2
    ${pkgs.curl}/bin/curl --silent --show-error --fail-with-body \
      -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
      --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
      --data-urlencode "text=$ESCAPED_MESSAGE" \
      --data-urlencode "parse_mode=MarkdownV2"
    CURL_EXIT_CODE=$?
    if [[ $CURL_EXIT_CODE -ne 0 ]]; then
        echo "Error: Failed to send Telegram message (curl exit code: $CURL_EXIT_CODE)." >&2
    else
        echo "Telegram notification sent successfully." >&2
    fi
    exit $CURL_EXIT_CODE
  '';

  escapeName =
    path:
    if path == "/" then
      "-" # Results in unit names like bcachefs-scrub--.service, which is valid.
    else
      lib.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "/" path);

  scrubServiceName = mountPoint: "bcachefs-scrub-${escapeName mountPoint}";
  scrubFailureNotifyServiceName =
    mountPoint: "bcachefs-scrub-failure-notify-${escapeName mountPoint}";
  scrubTimerName = mountPoint: "bcachefs-scrub-${escapeName mountPoint}";

in
{
  options.${namespace}.services.bcachefsScrubAuto = {
    enable = mkEnableOption (mdDoc "Periodic bcachefs scrub service with Telegram notifications");

    targetMountPoints = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "/mnt/bcachefs-main"
        "/srv/bcachefs-archive"
      ];
      description = mdDoc ''
        List of bcachefs mount points to target for scrubbing.
        The module will perform a sanity check to ensure these mount points
        are defined in `fileSystems` and are of type `bcachefs`.
      '';
    };

    schedule = mkOption {
      type = types.str;
      default = "weekly";
      example = "*-*-1,15 03:00:00";
      description = mdDoc ''
        When to run the scrubs automatically. Applies to all targeted mounts.
        Uses systemd.time OnCalendar= format. Timers include randomized delay.
        See `man systemd.time` for detailed syntax.
      '';
    };

    telegramTokenPath = mkOption {
      type = types.path;
      default = "/run/secrets/health_reporter_bot_api_token";
      description = mdDoc "Absolute path to the file containing the Telegram bot token.";
    };

    telegramChatIdPath = mkOption {
      type = types.path;
      default = "/run/secrets/telegram_chat_id";
      description = mdDoc "Absolute path to the file containing the Telegram chat ID.";
    };

    notifyOnStart = mkOption {
      type = types.bool;
      default = true;
      description = mdDoc "Send a Telegram notification when a scrub starts.";
    };

    notifyOnSuccess = mkOption {
      type = types.bool;
      default = true;
      description = mdDoc "Send a Telegram notification when a scrub completes successfully.";
    };

    notifyOnFailure = mkOption {
      type = types.bool;
      default = true;
      description = mdDoc "Send a Telegram notification if a scrub command fails.";
    };
  };

  # The config block defines the actual system configuration based on the options.
  # It's wrapped in mkIf cfg.enable so it only applies if the service is enabled.
  config = mkIf cfg.enable {
    # Assertions are evaluated to ensure valid configuration.
    assertions =
      [
        {
          assertion = cfg.enable -> (builtins.length cfg.targetMountPoints > 0);
          message = "${namespace}.services.bcachefsScrubAuto is enabled but no targetMountPoints are specified.";
        }
      ]
      ++ map (mountPoint: {
        assertion = builtins.any (fs: fs.fsType == "bcachefs" && fs.mountPoint == mountPoint) (
          lib.attrValues config.fileSystems
        );
        message = "${namespace}.services.bcachefsScrubAuto: Target mount point \"${mountPoint}\" is not a configured bcachefs filesystem in `fileSystems`.";
      }) cfg.targetMountPoints;

    # Define all systemd services as a single attribute set.
    systemd.services =
      let
        # Generate main scrub service definitions for each target.
        mainScrubServices = lib.listToAttrs (
          map (
            mountPoint:
            let
              sName = scrubServiceName mountPoint;
              fName = scrubFailureNotifyServiceName mountPoint; # For OnFailure
              startMsgTemplate = "🚀 Starting bcachefs scrub on host __HOSTNAME__ for mount point: ${mountPoint}";
              successMsgTemplate = "✅ Successfully completed bcachefs scrub on host __HOSTNAME__ for mount point: ${mountPoint}";
            in
            {
              name = sName; # This becomes the attribute name in the final set
              value = {
                # This is the service definition
                description = "Run bcachefs scrub on ${mountPoint}";
                path = [ pkgs.bcachefs-tools ]; # Ensures bcachefs-tools is in PATH
                serviceConfig = {
                  Type = "oneshot";
                  User = "root";
                  Group = "root";
                  ExecStartPre = mkIf cfg.notifyOnStart "+${telegramNotifierScript}/bin/bcachefs-scrub-notify ${escapeShellArg cfg.telegramTokenPath} ${escapeShellArg cfg.telegramChatIdPath} ${escapeShellArg startMsgTemplate}";
                  ExecStart = "${pkgs.bcachefs-tools}/bin/bcachefs data scrub ${escapeShellArg mountPoint}";
                  ExecStartPost = mkIf cfg.notifyOnSuccess "+${telegramNotifierScript}/bin/bcachefs-scrub-notify ${escapeShellArg cfg.telegramTokenPath} ${escapeShellArg cfg.telegramChatIdPath} ${escapeShellArg successMsgTemplate}";
                  OnFailure = mkIf cfg.notifyOnFailure [ "${fName}.service" ];
                };
              };
            }
          ) cfg.targetMountPoints
        );

        # Generate failure notification service definitions for each target.
        failureNotifyServices = lib.listToAttrs (
          map (
            mountPoint:
            let
              mainServiceName = scrubServiceName mountPoint; # For the log message
              failureServiceName = scrubFailureNotifyServiceName mountPoint;
              failMsgTemplate = "❌ ERROR: bcachefs scrub failed on host __HOSTNAME__ for mount point: ${mountPoint}! Check systemd logs: journalctl -u ${mainServiceName}\\.service";
            in
            {
              name = failureServiceName;
              value = mkIf cfg.notifyOnFailure {
                # The entire service is conditional
                description = "Notify Telegram about bcachefs scrub failure on ${mountPoint}";
                serviceConfig = {
                  Type = "oneshot";
                  User = "root";
                  ExecStart = "+${telegramNotifierScript}/bin/bcachefs-scrub-notify ${escapeShellArg cfg.telegramTokenPath} ${escapeShellArg cfg.telegramChatIdPath} ${escapeShellArg failMsgTemplate}";
                };
              };
            }
          ) cfg.targetMountPoints
        );
      in
      # Merge the main scrub services and the failure notification services.
      # If a value from failureNotifyServices is `false` (due to mkIf), it won't create an actual service.
      mainScrubServices // failureNotifyServices;

    # Define all systemd timers as a single attribute set.
    systemd.timers = lib.listToAttrs (
      map (
        mountPoint:
        let
          sName = scrubServiceName mountPoint; # Service to activate
          tName = scrubTimerName mountPoint; # Timer's own name
        in
        {
          name = tName; # Attribute name for the timer
          value = {
            # Timer definition
            description = "Timer for Bcachefs Scrub on ${mountPoint}";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = cfg.schedule;
              Unit = "${sName}.service"; # Explicitly state the service unit to activate
              Persistent = true;
              RandomizedDelaySec = "1h";
            };
          };
        }
      ) cfg.targetMountPoints
    );
  };
}
