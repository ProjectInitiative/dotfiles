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
  cfg = config.${namespace}.hosts.cargohold;
in
{
  options.${namespace}.hosts.cargohold = {
    enable = mkBoolOpt false "Whether to enable base cargohold NAS configuration";
    ipAddress = mkOpt types.str "192.168.1.100/24" "Static management IP address with CIDR"; # Example IP
    interface = mkOpt types.str "eth0" "Network interface for static IP"; # Example interface
    gateway = mkOpt types.str "192.168.1.1" "Default gateway"; # Example gateway
    bcachefsMountpoint = mkOpt types.str "/mnt/storage" "Path to mount bcachefs pool";
    # Add more NAS specific options here later if needed (e.g., Samba shares)
  };

  config = mkIf cfg.enable (
    # Reference the kernel package being used
    let
      kernel = config.boot.kernelPackages.kernel; # Use the kernel defined below or default

      # Fetch the source for the it87 driver
      # !!! REPLACE owner, repo, rev, and sha256 with actual values !!!
      it87-driver-src = pkgs.fetchFromGitHub {
        owner = "frankcrawford";
        repo = "it87";
        rev = "4bff981a91bf9209b52e30ee24ca39df163a8bcd";
        hash = "sha256-hjNph67pUaeL4kw3cacSz/sAvWMcoN2R7puiHWmRObM=";
      };

      # Define the package to build the kernel module
      it87-driver = config.boot.kernelPackages.callPackage (
        { stdenv, lib }:
        let
          # Define correct paths from Nix environment
          kernelBuildDir = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build";
          moduleInstallDir = "${placeholder "out"}/lib/modules/${kernel.modDirVersion}/kernel/drivers/hwmon"; # Matches Makefile's MOD_SUBDIR
        in
        stdenv.mkDerivation {
          pname = "it87-out-of-tree";
          version = "${kernel.version}-${lib.substring 0 7 it87-driver-src.rev}";

          src = it87-driver-src;

          nativeBuildInputs = kernel.moduleBuildDependencies;

          # Explicitly define build phase, overriding Makefile's KERNEL_BUILD calculation
          buildPhase = ''
            runHook preBuild
            echo "--- Building IT87 module ---"
            echo "Overriding KERNEL_BUILD=${kernelBuildDir}"
            # Pass KERNEL_BUILD directly to the make command for the 'modules' target.
            # This ensures the '-C' argument in that target uses the correct path.
            # Also pass M=$PWD explicitly.
            make modules KERNEL_BUILD="${kernelBuildDir}" M="$PWD"
            echo "--- Finished building IT87 module ---"
            runHook postBuild
          '';

          # Explicitly define install phase, bypassing Makefile's install target
          installPhase = ''
            runHook preInstall
            echo "--- Installing IT87 module manually ---"
            # Create the correct destination directory inside $out
            mkdir -p "${moduleInstallDir}"
            # Copy the built module (assuming name is it87.ko based on Makefile)
            #  # Rename the output file before copying
            mv it87.ko it87-oot.ko
            cp it87-oot.ko "${moduleInstallDir}/"
            echo "Installed it87-oot.ko to ${moduleInstallDir}"
            # DO NOT RUN depmod. NixOS handles module dependencies.
            runHook postInstall
          '';

          meta = with lib; {
            description = "Out-of-tree kernel module for ITE IT8xxx Super I/O chips (inc. IT8613E)";
            license = licenses.gpl2Only; # Verify license
            platforms = platforms.linux;
            maintainers = [ maintainers.kylepzak ];
          };
        }
      ) { }; # Pass empty attribute set for callPackage

      # --- Configuration Section (Define parameters here) ---
      pwmEnablePath = "/sys/class/hwmon/hwmon2/pwm3_enable"; # <---- ADJUST TO YOUR SYSTEM
      pwmControlPath = "/sys/class/hwmon/hwmon2/pwm3"; # <---- ADJUST TO YOUR SYSTEM
      tempThreshold = 45; # Temperature threshold in Celsius
      pwmLow = 100; # PWM value (0-255) below threshold (ensure >= min effective PWM)
      pwmHigh = 255; # PWM value (0-255) at/above threshold
      pwmDefault = 128; # Default PWM if no drive temps are readable
      checkInterval = "2m"; # How often the timer runs the check
      # --- End Configuration Section ---

      # Shell script to perform the check and set the fan speed
      hddFanControlScript = pkgs.writeShellScriptBin "hdd-fan-control-hottest" ''
        #!${pkgs.runtimeShell}
        set -eu # Exit on error, unset variables

        # --- Use configuration passed from Nix ---
        PWM_ENABLE="${pwmEnablePath}"
        PWM_CONTROL="${pwmControlPath}"
        TEMP_THRESHOLD="${toString tempThreshold}"
        PWM_LOW="${toString pwmLow}"
        PWM_HIGH="${toString pwmHigh}"
        DEFAULT_PWM="${toString pwmDefault}"

        # --- Script Logic ---
        max_temp=-1 # Initialize max temp to a value lower than possible temps
        hottest_drive="none"
        temp_found=0 # Flag to track if any valid temp was found

        echo "INFO: Starting hottest drive temperature check..."

        # Create a temporary file to hold the list of disk devices
        DEVICE_LIST_FILE=$(${pkgs.coreutils}/bin/mktemp)
        # Ensure cleanup on exit
        trap '${pkgs.coreutils}/bin/rm -f "$DEVICE_LIST_FILE"' EXIT

        # Get disk devices using lsblk JSON output and jq parser
        if ! ${pkgs.util-linux}/bin/lsblk -Jdno NAME | ${pkgs.jq}/bin/jq -r '.blockdevices[] .name | "/dev/\(.)"' > "$DEVICE_LIST_FILE"; then
          echo "ERROR: Failed to list disk devices using lsblk/jq." >&2
          exit 1 # Exit if device listing fails
        fi

        echo "INFO: Found drives to check:"
        cat "$DEVICE_LIST_FILE"

        # Loop through the device list file
        while IFS= read -r device_path; do
          # Skip empty lines if any
          if [ -z "$device_path" ]; then continue; fi

          echo "INFO: Checking temperature for $device_path..."
          # Get temperature using smartctl, grep for the line, awk the value, take first result
          # Redirect stderr to /dev/null to suppress smartctl errors for non-supporting drives
          current_temp=$(${pkgs.smartmontools}/bin/smartctl -A "$device_path" -d auto 2>/dev/null | ${pkgs.gnugrep}/bin/grep -i Temperature_Celsius | ${pkgs.gawk}/bin/awk '{print $10}' | ${pkgs.coreutils}/bin/head -n 1)

          # Check if we got a numeric temperature
          if ! [[ "$current_temp" =~ ^[0-9]+$ ]]; then
            echo "WARN: No valid temperature reading obtained from $device_path." >&2
            continue # Skip to the next drive
          fi

          echo "INFO: Temperature for $device_path: $current_temp C"
          temp_found=1 # Mark that we found at least one valid temperature

          # Update maximum temperature if current drive is hotter
          if [ "$current_temp" -gt "$max_temp" ]; then
            max_temp="$current_temp"
            hottest_drive="$device_path"
          fi

        done < "$DEVICE_LIST_FILE"
        # Temp file is removed by EXIT trap

        # --- Determine Fan Speed ---
        TARGET_PWM="$DEFAULT_PWM" # Start with default

        if [ "$temp_found" -eq 0 ]; then
          echo "ERROR: Could not read a valid temperature from any drive. Setting default PWM ($DEFAULT_PWM)." >&2
        else
          echo "INFO: Hottest drive found: $hottest_drive at $max_temp C. Threshold is $TEMP_THRESHOLD C."
          # Set PWM based on the highest temperature found
          if [ "$max_temp" -ge "$TEMP_THRESHOLD" ]; then
            TARGET_PWM="$PWM_HIGH"
          else
            TARGET_PWM="$PWM_LOW"
          fi
        fi

        # --- Set Fan Speed ---
        # Check if control files are writable first
        if [ ! -w "$PWM_ENABLE" ] || [ ! -w "$PWM_CONTROL" ]; then
          echo "ERROR: Cannot write to PWM control files: $PWM_ENABLE / $PWM_CONTROL. Cannot set fan speed." >&2
          exit 1 # Exit if controls aren't available/writable
        fi

        echo "INFO: Setting fan PWM ($PWM_CONTROL) to: $TARGET_PWM"
        # Ensure manual mode is enabled (important!)
        echo 1 > "$PWM_ENABLE"
        # Set the target PWM value
        echo "$TARGET_PWM" > "$PWM_CONTROL"

        echo "INFO: Hottest drive temperature check complete."
      ''; # End of script string

    in
    {
      sops = {
        secrets = {
          readonly_backup_access_key_id = {};
          readonly_backup_secret_access_key = {};
        };
        templates."rclone.conf" = {
          mode = "0400";
          content = ''
            [s3]
            type = s3
            access_key_id = ${config.sops.placeholder."readonly_backup_access_key_id"}
            secret_access_key = ${config.sops.placeholder."readonly_backup_secret_access_key"}
            provider = Other
            s3_force_path_style = true
            endpoint = http://172.16.1.50:31292
          '';
        };
      };

      # --- Systemd Service Definition ---
      systemd.services.hddFanControl = {
        description = "Hottest Drive Temperature Fan Control Service";
        # Ensure all commands used in the script are in the path
        path = with pkgs; [
          smartmontools # for smartctl
          coreutils # for head, mktemp, rm, cat
          gawk # for awk
          gnugrep # for grep
          jq # for parsing lsblk JSON
          util-linux # for lsblk
          runtimeShell # Provides the shell itself (e.g., bash)
        ];
        serviceConfig = {
          Type = "oneshot"; # Run script once and exit
          User = "root"; # Needs root for smartctl and /sys writes
          ExecStart = "${hddFanControlScript}/bin/hdd-fan-control-hottest";
        };
      };

      # --- Systemd Timer Definition ---
      systemd.timers.hddFanControl = {
        description = "Run Hottest Drive Fan Control Script Periodically";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1min"; # Run 1 minute after boot
          OnUnitActiveSec = checkInterval; # Run again based on variable above
          Unit = "hddFanControl.service"; # Service to activate
        };
      };

      # Base system packages
      environment.systemPackages = with pkgs; [
        bcachefs-tools
        linuxPackages_latest.perf
        smartmontools
        lsof
        pciutils
        iperf3
        lm_sensors
        # Add NAS related tools like samba, nfs-utils if needed
      ];

      # Enable bcachefs support
      boot.supportedFilesystems = [ "bcachefs" ];

      boot.kernelModules = [
        "bcachefs"
        "it87-oot"
      ];
      # Consider using latest kernel if needed for bcachefs features
      boot.kernelPackages = pkgs.linuxPackages_latest;
      # Add the out-of-tree module package here
      boot.extraModulePackages = [ it87-driver ];

      boot.kernelParams = [
        "nomodeset"
        "intel_idle.max_cstate=1"
      ];

      console.enable = true;
      # enable GPU drivers
      hardware.enableRedistributableFirmware = true;
      hardware.firmware = [ pkgs.linux-firmware ];

      # Enable SSH access
      services.openssh = {
        enable = true;
        settings = {
        };
      };

      # Networking using systemd-networkd
      networking = {
        useDHCP = true; # Disable global DHCP
        # interfaces = { }; # Clear interfaces managed elsewhere
        nameservers = [
          cfg.gateway # Use gateway as primary DNS
          "1.1.1.1" # Cloudflare DNS
          "9.9.9.9" # Quad9 DNS
        ];
        # defaultGateway = cfg.gateway; # Set via systemd-networkd route
        # firewall.allowedTCPPorts = [
        #   22 # SSH
        #   5201 # iperf
        #   # Add ports for NAS services (e.g., Samba: 139, 445)
        # ];
        networkmanager.enable = false; # Ensure NetworkManager is disabled
      };

      systemd.network = {
        enable = false;
        networks."10-${cfg.interface}" = {
          matchConfig.Name = cfg.interface;
          networkConfig = {
            DHCP = "no";
            Address = cfg.ipAddress;
            Gateway = cfg.gateway;
            DNS = config.networking.nameservers; # Use nameservers defined above
            IPv6AcceptRA = "no";
          };
          # Explicit default route
          routes = [
            {
              Gateway = cfg.gateway;
              Destination = "0.0.0.0/0";
            }
          ];
        };
      };

      home-manager.backupFileExtension = "backup";
      # Enable common project modules if needed
      projectinitiative = {
        services = {

          eternal-terminal = enabled;

          bcachefs-fs-options.settings = {
            "27cac550-3836-765c-d107-51d27ab4a6e1" = {
              foreground_target = "cache.nvme1";
              background_target = "hdd";
              promote_target = "hdd";
            };
          };

          health-reporter = {
            enable = true;
            telegramTokenPath = config.sops.secrets.health_reporter_bot_api_token.path;
            telegramChatIdPath = config.sops.secrets.telegram_chat_id.path;
            excludeDrives = [
              "loop"
              "ram"
              "sr"
            ]; # Default exclusions
            reportTime = "08:00"; # Send report at 8 AM
          };
        };
        suites = {
          monitoring = enabled;
          loft = {
            enableClient = true;
          };
          bcachefs-utils = {
            enable = true;
            parentSubvolume = "/mnt/pool";
          };
        };
        system = {
          console-info.ip-display = enabled;

          nix-config = enabled;

          bcachefs-kernel = {
            enable = false;
            # rev = "";
            # hash = "";
            debug = true;
          };
          bcachefs-module = {
            enable = false;
            rev = ""; # Or specify a specific commit hash
            hash = "";
            debug = true;
          };

        };
        networking.tailscale = {
          enable = true; # Example: Enable Tailscale
          ephemeral = false;
          extraArgs = [ "--accept-routes" ];
        };
        # Add other services like Samba, NFS configuration here
        # services.samba = { enable = true; /* ... */ };
      };
      
      # Enable the sync-host service for automated backup tasks
      services.sync-host = {
        enable = true;
        telegram = {
          tokenPath = config.sops.secrets.health_reporter_bot_api_token.path;
          chatIdPath = config.sops.secrets.telegram_chat_id.path;
        };
        # Configure rclone remotes for backup (example configuration)
        rcloneRemotes = [ "s3" ]; # Add your rclone remotes here
        rcloneConfigPath = config.sops.templates."rclone.conf".path; # Path to rclone config template
        disableRTCWake = false; # Enable RTC wake by default
        wakeUpDelay = "168h"; # Wake up a week after last backup
        coolOffTime = "4h"; # Wait 4 hour after sync completion before shutdown for filesystem operations
        localTargetPath = "/mnt/pool/rclone/";
      };

      # Set the state version
      system.stateVersion = "24.05"; # Adjust as needed
    }
  );
}
