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

  rev = "4cf57c44a99fd9f62098fbbb8129b2a84c78e7a7";
  hash = "sha256-BresZiahFbm7sD7nlSnKtFNB1PQxT+/PocI4RP7EyzY=";  

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
  options.${namespace}.system.bcachefs-kernel = {
    enable = mkEnableOption "custom bcachefs kernel with read_fua_test support";

    rev = mkOption {
      type = types.str;
      default = rev; # Or a specific tag like "bcachefs-v6.X"
      description = "Git branch, tag, or commit hash of Kent Overstreet's bcachefs repository to use";
    };

    hash = mkOption {
      type = types.str;
      default = hash;
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
    environment.systemPackages = with pkgs; [
      bcachefs-tools
      linuxPackages_custom_bcachefs.perf
    ];
  };
}
