# /etc/nixos/modules/custom-bcachefs.nix
{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;

let
  cfg = config.${namespace}.system.bcachefs-kernel;

  defaultRev = "63ea3cf07639ec8ef5bd2c3f457eb54b6cd33198";
  defaultHash = "sha256-dY0yb0ZO0L5zOdloasqyEU80bitr1VNdmoyvxJv/sYE=";

  kernelSrc = pkgs.fetchFromGitHub {
    owner = "koverstreet";
    repo = "bcachefs";
    rev = cfg.rev;
    hash = cfg.hash;
  };

  versionInfo =
    pkgs.runCommand "bcachefs-kernel-version-info"
      {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gnused
        ];
        src = kernelSrc;
      }
      ''
        cd $src

        VER=$(grep -E '^VERSION\s*=' Makefile | sed 's/.*= *//')
        PL=$(grep -E '^PATCHLEVEL\s*=' Makefile | sed 's/.*= *//')
        SL=$(grep -E '^SUBLEVEL\s*=' Makefile | sed 's/.*= *//')
        EXTRA=$(grep -E '^EXTRAVERSION\s*=' Makefile | sed 's/.*= *//') # e.g., -rc4

        # version: This is the full version string, often used for uname -r
        # Example: 6.15.0-rc4
        kernelVersion="$VER.$PL.$SL$EXTRA"

        # modDirVersion: This needs to match what the kernel build system uses for the /lib/modules/ directory.
        # Given the Makefile and the error, it's the same as kernelVersion in this case.
        # Example: 6.15.0-rc4
        kernelModDirVersion="$VER.$PL.$SL$EXTRA"

        mkdir -p $out
        echo -n "$kernelVersion" > $out/version         # Will contain e.g., 6.15.0-rc4
        echo -n "$kernelModDirVersion" > $out/modDirVersion # Will contain e.g., 6.15.0-rc4

        if [ -z "$VER" ] || [ -z "$PL" ] || [ -z "$SL" ]; then
          echo "Error: Failed to parse base version components from Makefile."
          exit 1
        fi
        if [ -z "$kernelVersion" ]; then # EXTRA can be empty, so check for base version at least
            if [ -z "$VER" ] && [ -z "$PL" ] && [ -z "$SL" ]; then
                echo "Error: Failed to construct kernelVersion because base components are missing."
                exit 1
            fi
        fi
        if [ -z "$kernelModDirVersion" ]; then # EXTRA can be empty
            if [ -z "$VER" ] && [ -z "$PL" ] && [ -z "$SL" ]; then
                echo "Error: Failed to construct kernelModDirVersion because base components are missing."
                exit 1
            fi
        fi
      '';

  linux_bcachefs =
    { buildLinux, ... }@args:
    buildLinux (
      args
      // {
        version = builtins.readFile (versionInfo + "/version");
        modDirVersion = builtins.readFile (versionInfo + "/modDirVersion");

        src = kernelSrc;
        hardeningEnable = [ "fortify" ];

        structuredExtraConfig =
          with lib.kernel;
          {
            BCACHEFS_FS = yes;
            BCACHEFS_QUOTA = yes;
            BCACHEFS_POSIX_ACL = yes;
          }
          // (
            if cfg.debug then
              {
                BCACHEFS_DEBUG = yes;
                BCACHEFS_TESTS = yes;
              }
            else
              { }
          );
      }
    );

  customKernel = pkgs.callPackage linux_bcachefs {
    # If the rustfmt warning persists and you want to try addressing it:
    # nativeBuildInputs = (args.nativeBuildInputs or []) ++ [ pkgs.rustfmt ];
  };
  linuxPackages_custom_bcachefs = pkgs.linuxPackagesFor customKernel;

in
{

  ###############TODO################
  # REMOVE AFTER MAINLINE MERGED
  # imports = [
  #   ./bcachefs.nix
  # ];

  # Disable the original, conflicting bcachefs module from nixpkgs
  # disabledModules = [ "tasks/filesystems/bcachefs.nix" ];

  ###############TODO################

  options.${namespace}.system.bcachefs-kernel = {
    enable = mkEnableOption "custom bcachefs kernel with read_fua_test support";

    rev = mkOption {
      type = types.str;
      default = defaultRev; # Or a specific tag like "bcachefs-v6.X"
      description = "Git branch, tag, or commit hash of Kent Overstreet's bcachefs repository to use";
    };

    hash = mkOption {
      type = types.str;
      default = defaultHash;
      description = "SHA256 hash of the source code tarball (use nix-prefetch-github or run build once)";
      example = "sha256-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG=";
    };

    debug = mkOption {
      type = types.bool;
      default = true;
      description = "Enable bcachefs debug features";
    };
  };

  config = mkIf cfg.enable {
    boot.kernelPackages = mkForce linuxPackages_custom_bcachefs;
    boot.supportedFilesystems = [ "bcachefs" ];
    # If enabled, NixOS will set up a kernel that will boot on crash, and leave the user in systemd rescue to be able to save the crashed kernel dump at /proc/vmcore. It also activates the NMI watchdog.
    boot.crashDump.enable = true;
    environment.systemPackages = with pkgs; [
      bcachefs-tools
      linuxPackages_custom_bcachefs.perf
    ];

    ###############TODO################
    # REMOVE AFTER MAINLINE MERGED

    # This part is still useful to ensure the base modules are declared,
    # though the underlying nixpkgs module also adds them.
    # boot.initrd.availableKernelModules = [ "bcachefs" "sha256" ];

    # boot.initrd.systemd.extraBin = {
    #   "bcachefs" = "${pkgs.bcachefs-tools}/bin/bcachefs";
    # };

    ###################################

    # This script runs directly during `nixos-rebuild switch` to check if the
    # custom kernel version or git revision has changed.
    system.activationScripts.reboot-check =
      let
        # The file where we store the last known version identifier.
        versionStateFile = "/var/lib/kernel-and-module-version";
        # Create a unique identifier from the kernel version and the module revision.
        currentVersionIdentifier = "${builtins.readFile (versionInfo + "/version")}-${cfg.rev}";
      in
      {
        # This script should run late in the activation process.
        deps = [ "users" ];
        text = ''
          # The activation environment is minimal, so we use full paths to binaries.
          ECHO="${pkgs.coreutils}/bin/echo"
          CAT="${pkgs.coreutils}/bin/cat"
          TOUCH="${pkgs.coreutils}/bin/touch"

          # Check if the old version file exists and read it.
          if [ -f ${versionStateFile} ]; then
            OLD_VERSION_IDENTIFIER=$($CAT ${versionStateFile})
          else
            # If it doesn't exist, this is the first run.
            OLD_VERSION_IDENTIFIER="none"
          fi

          $ECHO "Current identifier: ${currentVersionIdentifier}"
          $ECHO "Previous identifier: $OLD_VERSION_IDENTIFIER"

          # If the identifier has changed, a reboot is needed.
          if [ "${currentVersionIdentifier}" != "$OLD_VERSION_IDENTIFIER" ]; then
            $ECHO "Kernel version or module revision has changed. Signaling for a reboot."
            $TOUCH /var/run/reboot-required
          else
            $ECHO "No kernel change detected."
          fi

          # Update the state file with the new identifier for the next check.
          $ECHO -n "${currentVersionIdentifier}" > ${versionStateFile}
        '';
      };

  };
}
