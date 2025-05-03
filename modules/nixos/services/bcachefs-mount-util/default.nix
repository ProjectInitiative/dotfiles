# /path/to/your/nixos/modules/bcachefs-mount-service.nix
{ config, lib, pkgs, namespace ? "mySystem", ... }:

with lib;

let
  # Define configuration options under a specific namespace
  cfg = config.${namespace}.systemd.bcachefsMountUnits; # Using systemd.* namespace might be clearer

in
{
  options.${namespace}.systemd.bcachefsMountUnits = {
    enable = mkEnableOption "Generate systemd services to mount declared bcachefs filesystems (Workaround for boot issues)";

    excludeMountPoints = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "/mnt/bcachefs-manual-mount" ];
      description = ''
        List of exact mount points (as defined in `fileSystems`) to exclude
        from having a systemd mount service generated.
      '';
    };

    # Optional: Allow customizing dependencies if needed later
    # after = mkOption { type = types.listOf types.str; default = ["local-fs.target"]; };
    # wantedBy = mkOption { type = types.listOf types.str; default = ["multi-user.target"]; };

    description = ''
      This module provides a workaround for potential issues mounting bcachefs
      filesystems via the standard NixOS `/etc/fstab` generation at early boot.
      It generates individual systemd `.service` units for each `bcachefs` filesystem
      declared in `config.fileSystems`.

      WARNING: If NixOS *also* tries to mount these filesystems via fstab,
      conflicts or race conditions might occur. If you enable this module because
      standard mounting fails, you might need to prevent NixOS from attempting
      the standard mount for these specific filesystems (e.g., by commenting them
      out in `config.fileSystems`, although that prevents auto-detection here,
      or potentially finding another way if NixOS options evolve).
      This module assumes the systemd service is the *intended* way to mount these filesystems.
    '';
  };

  config = mkIf cfg.enable (
    let
      # --- Auto-detect bcachefs mounts from config.fileSystems ---
      bcachefsMounts = lib.attrsets.filterAttrs (name: value:
        value.fsType == "bcachefs" && !(elem name cfg.excludeMountPoints)
      ) config.fileSystems;

      # --- Helper function to format mount options ---
      # Takes the list of options from fileSystems config
      mountOptsString = optsList:
        let
          # Default options if none are provided explicitly (bcachefs might not need 'defaults' like ext4)
          # defaults = if optsList == [] then ["defaults"] else optsList; # Decide if you want implicit defaults
          defaults = optsList; # Currently assumes explicit options are sufficient
        in
        # Return empty string if no options, otherwise "-o comma,separated,list"
        lib.optionalString (defaults != []) "-o ${lib.escapeShellArg (lib.strings.concatStringsSep "," defaults)}";

      # --- Generate Systemd Services for each detected mount ---
      generatedServices = lib.attrsets.mapAttrs' (mountPoint: fsConfig:
        let
          # Ensure required fields exist
          device = fsConfig.device or (throw "Device not specified for bcachefs filesystem at ${mountPoint}");
          options = fsConfig.options or []; # Default to empty list if options are missing

          # Generate names and option string
          serviceName = "mount-bcachefs-${lib.escapeSystemdPath mountPoint}.service";
          optsStr = mountOptsString options;
        in
        lib.nameValuePair serviceName {
          description = "Mount bcachefs filesystem ${mountPoint}";
          # Specify required binaries in PATH
          path = [ pkgs.bcachefs-tools pkgs.util-linux pkgs.coreutils ];

          # --- Dependencies ---
          # Should run after basic file systems are up, potentially after devices are fully available
          after = [ "local-fs.target" ]; # Or customize via cfg.after
          # Ensures the mount happens before user sessions start requiring these mounts
          wantedBy = [ "multi-user.target" ]; # Or customize via cfg.wantedBy

          # --- Service Configuration ---
          serviceConfig = {
            Type = "oneshot";
            # Keep the service active to represent the mounted state
            RemainAfterExit = true;

            # Create mount point directory before attempting mount; ignore error if it exists
            ExecStartPre = "+${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg mountPoint}";

            # The core mount logic
            ExecStart = ''
              # Check if already mounted first
              if ! ${pkgs.util-linux}/bin/mountpoint -q ${lib.escapeShellArg mountPoint}; then
                echo "Attempting to mount ${device} at ${mountPoint} via systemd service ${serviceName} with options: [${options}]"
                # Execute the mount command
                ${pkgs.util-linux}/bin/mount -t bcachefs ${optsStr} ${lib.escapeShellArg device} ${lib.escapeShellArg mountPoint}
              else
                echo "${mountPoint} is already mounted (checked by systemd service ${serviceName})."
                # Exit successfully if already mounted
                exit 0
              fi
            '';

            # Optional: Define how to unmount if the service is stopped
            # ExecStop = "${pkgs.util-linux}/bin/umount ${lib.escapeShellArg mountPoint}";
          };
        }
      ) bcachefsMounts; # End mapAttrs'

    in # --- Return the generated services ---
    {
      systemd.services = generatedServices;

      # Add a warning assertion about potential conflicts with fstab mounts
      assertions = [{
          assertion = true; # This doesn't prevent build, just warns at eval time
          message = ''
            WARNING (${namespace}.systemd.bcachefsMountUnits): This module is enabled.
            Ensure that NixOS is not also attempting to mount the following bcachefs filesystems
            via /etc/fstab, as this could cause conflicts:
            ${lib.strings.concatStringsSep "\n" (lib.attrsets.keys bcachefsMounts)}
            You might need to adjust 'config.fileSystems' entries if standard mounting causes issues.
          '';
      }];
    }
  ); # End mkIf
}
