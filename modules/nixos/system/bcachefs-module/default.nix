{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;

let
  # Configuration options for this module are under cfg
  cfg = config.${namespace}.system.bcachefs-module;

  # Define kernel package once for clarity and lazy access
  kernel = config.boot.kernelPackages.kernel;

  # --- Define the bcachefs module derivation in the module's top-level scope ---
  # This derivation definition is lazy; it will only be evaluated if cfg.enable is true
  # and something in the config section actually references 'bcachefsDrv'.
  bcachefsDrv = pkgs.stdenv.mkDerivation {
    pname = "bcachefs-module";
    version = "git-${builtins.substring 0 7 cfg.rev}";

    # Fetch the source code based on configured rev and hash
    src = pkgs.fetchFromGitHub {
      owner = "koverstreet";
      repo = "bcachefs";
      rev = cfg.rev;
      hash = cfg.hash; # Hash comes directly from config
    };

    # Inherit build dependencies (headers, scripts) from the kernel package
    nativeBuildInputs = kernel.moduleBuildDependencies;

    # Define variables accessible to the Make commands below.
    # KERNEL_DIR points to the kernel build directory (read-only).
    # KERNELRELEASE ensures the module targets the correct kernel version.
    # INSTALL_MOD_PATH tells 'modules_install' where to put the final .ko file within $out.
    makeFlags = [
      "KERNELRELEASE=${kernel.modDirVersion}"
      "KERNEL_DIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      "INSTALL_MOD_PATH=$(out)"
    ];

    # Change to the directory containing the module's specific Makefile
    # before the buildPhase starts.
    preBuild = ''
      cd fs/bcachefs
      pwd # Add for debugging - shows current directory before buildPhase
      ls -l # Add for debugging - shows files including Makefile
    '';

    # Build Phase:
    # Invoke the main kernel Makefile (-C) and tell it where the
    # external module source code is located (M=$(pwd))
    buildPhase = ''
      runHook preBuild # Executes the 'cd fs/bcachefs' from preBuild hook
      echo "Building bcachefs module (source: $(pwd)) using kernel build dir: ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      # Use make flags defined above
      make -C "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build" M=$(pwd) modules
      runHook postBuild
    '';

    # Install Phase:
    # Copy the compiled module (.ko file) from the build directory (fs/bcachefs)
    # into the expected location within the output path ($out).
    installPhase = ''
      runHook preInstall
      # Target directory structure expected by boot.extraModulePackages
      local KMOD_DIR="$out/lib/modules/${kernel.modDirVersion}/extra"
      mkdir -p "$KMOD_DIR"
      echo "Installing bcachefs.ko from $(pwd) to $KMOD_DIR..."
      # Verify the .ko file was actually created before trying to copy it
      if [ ! -f bcachefs.ko ]; then
          echo "ERROR: bcachefs.ko not found in $(pwd) after build!"
          ls -lR . # List current dir contents recursively for debugging
          exit 1
      fi
      cp bcachefs.ko "$KMOD_DIR/"
      runHook postInstall
    '';

    # Meta information about this derivation
    meta = {
      description = "bcachefs filesystem kernel module (built via NixOS module config)";
      homepage = "https://bcachefs.org/";
      license = licenses.gpl2Only; # Use the specific license
      platforms = platforms.linux; # This module is Linux-specific
      # maintainers = with maintainers; [ /* Your Nixpkgs username */ ]; # Optional: add yourself
    };
  }; # <<< End of bcachefsDrv derivation definition

in
# End of the top-level 'let' block for this module file
{
  # --- Options Definition ---
  # Defines the configuration interface for this module.
  options.${namespace}.system.bcachefs-module = {
    enable = mkEnableOption "Whether to enable building bcachefs as a kernel module";

    autoload = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to automatically load the bcachefs module at boot";
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable verbose debugging output during module loading";
    };

    rev = mkOption {
      type = types.str;
      default = "master"; # Or consider a more stable default like a tag
      description = "Git revision (branch, tag, or commit hash) for bcachefs source";
    };

    hash = mkOption {
      type = types.str;
      default = ""; # Force user to provide hash for safety and reproducibility
      description = "Expected SHA256 hash for the specified git revision. Required if enable is true.";
      example = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
  };

  # --- Configuration Definition ---
  # Defines how the system configuration is modified based on the options.
  # This block is included in the final system config only if cfg.enable is true.
  config = mkIf cfg.enable {

    # Assertion to ensure hash is provided when enabled. Checked during evaluation.
    assertions = [
      {
        assertion = cfg.hash != "" && cfg.hash != lib.fakeSha256;
        message = ''
          The option ${namespace}.system.bcachefs-module.hash must be set to a valid SHA256 hash
          when ${namespace}.system.bcachefs-module.enable is true.
          You can get the hash by initially setting it to lib.fakeSha256 (or an empty string "")
          and running the build; Nix will report the expected hash on failure.
        '';
      }
    ];

    # Add the compiled kernel module derivation to the list NixOS uses
    boot.extraModulePackages = [ bcachefsDrv ];

    # Conditionally add the module to the autoload list (/etc/modules-load.d)
    boot.kernelModules = mkIf cfg.autoload [ "bcachefs" ];

    # Ensure the userspace tools package is installed
    environment.systemPackages = with pkgs; [ bcachefs-tools ];

    # Declare filesystem support (relevant for initrd, mount helpers, etc.)
    boot.supportedFilesystems = [ "bcachefs" ];

    # Add post-boot commands for debugging module loading if enabled
    boot.postBootCommands = mkIf cfg.debug ''
      echo "Attempting to load bcachefs kernel module (${bcachefsDrv.name})..." >&2
      if modprobe bcachefs; then
        echo "bcachefs module loaded successfully!" >&2
        lsmod | grep bcachefs || echo "Warning: bcachefs module loaded but not listed by lsmod?" >&2
      else
        echo "ERROR: Failed to load bcachefs module. Check dmesg for details." >&2
        dmesg | grep -i bcachefs # Show relevant dmesg lines
      fi
    '';

  }; # End of mkIf cfg.enable block

} # End of the module definition (returned attribute set)
