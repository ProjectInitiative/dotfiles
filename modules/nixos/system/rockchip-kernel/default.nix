# /etc/nixos/modules/custom-patched-kernel.nix
{
  config,
  lib,
  pkgs,
  namespace, # This should be the namespace you use for your custom options
  ...
}:

with lib;

let
  # Configuration for this custom kernel module
  cfg = config.${namespace}.system.patched-kernel;

  # Fetch the kernel source based on configuration
  kernelSrc = pkgs.fetchFromGitHub {
    owner = cfg.kernelOwner;
    repo = cfg.kernelRepo;
    rev = cfg.kernelRev;
    hash = cfg.kernelSourceHash;
  };

  # Derivation to extract version information from the kernel's Makefile
  versionInfo =
    pkgs.runCommand "custom-kernel-version-info"
      {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gnused
        ];
        src = kernelSrc; # Use the fetched kernel source
      }
      ''
        cd $src

        # Extract version components from the Makefile
        VER=$(grep -E '^VERSION\s*=' Makefile | sed 's/.*= *//')
        PL=$(grep -E '^PATCHLEVEL\s*=' Makefile | sed 's/.*= *//')
        SL=$(grep -E '^SUBLEVEL\s*=' Makefile | sed 's/.*= *//')
        EXTRA=$(grep -E '^EXTRAVERSION\s*=' Makefile | sed 's/.*= *//') # e.g., -rc4, -custom1

        # Construct the full kernel version string (e.g., 6.14.0-rc6-custom)
        kernelVersion="$VER.$PL.$SL$EXTRA"

        # Construct the module directory version string
        # For most kernels, this is identical to kernelVersion.
        # Some kernels might have a slightly different scheme, but this is a common default.
        kernelModDirVersion="$VER.$PL.$SL$EXTRA"

        # Output the versions to files
        mkdir -p $out
        echo -n "$kernelVersion" > $out/version
        echo -n "$kernelModDirVersion" > $out/modDirVersion

        # Basic validation
        if [ -z "$VER" ] || [ -z "$PL" ] || [ -z "$SL" ]; then
          echo "Error: Failed to parse base version components (VERSION, PATCHLEVEL, SUBLEVEL) from Makefile." >&2
          exit 1
        fi
        if [ -z "$kernelVersion" ]; then
          echo "Error: Failed to construct kernelVersion string." >&2
          exit 1
        fi
        if [ -z "$kernelModDirVersion" ]; then
          echo "Error: Failed to construct kernelModDirVersion string." >&2
          exit 1
        fi
      '';

  # Define the custom/patched kernel package
  linux_patched =
    { buildLinux, fetchpatch, ... }@args: # Added fetchpatch for patch handling
    buildLinux (
      args
      // {
        # Use the dynamically determined versions
        version = builtins.readFile (versionInfo + "/version");
        modDirVersion = builtins.readFile (versionInfo + "/modDirVersion");

        src = kernelSrc; # Use the fetched kernel source

        # Apply any additional patches specified in the configuration
        # Patches are applied in the order they are listed.
        patches = cfg.extraPatches;

        # Standard kernel hardening options (optional, adjust as needed)
        hardeningEnable = [ "fortify" ]; # Example, can be customized or removed

        # Kernel configuration
        # This section needs to be tailored for your Rockchip board (e.g., Radxa E52C)
        # and the base configuration of the kernel source you are using (e.g., Collabora's).
        # Start by ensuring essential Rockchip drivers and features are enabled.
        structuredExtraConfig =
          with lib.kernel;
          {
            # --- Essential ARM64 and Rockchip Options (Examples - VERIFY AND CUSTOMIZE) ---
            ARCH_ROCKCHIP = yes;
            ROCKCHIP_PM_DOMAINS = yes; # Rockchip Power Management Domains

            # Interrupt Controller (GIC - Generic Interrupt Controller)
            IRQ_GIC_V3 = yes;
            IRQ_GIC_V3_ITS = yes; # ITS (Interrupt Translation Service) for GICv3

            # Console Support (ensure your serial console works)
            SERIAL_8250 = yes;
            SERIAL_8250_CONSOLE = yes;
            SERIAL_8250_ROCKCHIP = yes; # If a specific Rockchip 8250 driver is used/needed

            # Storage (MMC/SD/eMMC - Essential for booting)
            MMC = yes;
            # Choose the correct Rockchip MMC/SDHCI driver for your SoC (RK3582/RK3588)
            # Common ones include:
            MMC_ROCKCHIP = yes; # General Rockchip MMC driver
            DW_MMC = yes; # DesignWare MMC interface
            DW_MMC_ROCKCHIP = yes; # Rockchip specific DesignWare MMC

            # Pin Control and Clocking (Crucial for board bring-up)
            PINCTRL = yes;
            PINCTRL_ROCKCHIP = yes; # Or a more specific one for RK358x series
            COMMON_CLK = yes;
            COMMON_CLK_ROCKCHIP = yes; # Or a more specific one for RK358x series

            # Reset Controller
            RESET_CONTROLLER = yes;
            RESET_ROCKCHIP = yes;

            # Device Tree Support
            OF_EARLY_FLATTREE = yes; # For early device tree parsing

            # --- End Essential Rockchip Options ---

            # Add any configurations required by your specific patches or kernel source
            # For example, if a patch enables a new driver:
            # MY_NEW_ROCKCHIP_DRIVER = module; # or yes

          }
          // ( # Conditionally add debug options
            if cfg.debug then
              {
                DEBUG_KERNEL = yes;
                DEBUG_INFO = yes;
                # Add other relevant debug Kconfig options if needed
                # For GIC issues, you might look for GIC_DEBUG or IRQ_DEBUG options
                # DEBUG_IRQCHIP = yes; # Example, check Kconfig for actual name
              }
            else
              { }
          );

        # If the kernel source you are using (e.g., Collabora's) provides a
        # specific defconfig for your board (e.g., rockchip_linux_defconfig, rk3588_defconfig),
        # you might consider using it as a base. However, `buildLinux` in Nixpkgs
        # typically starts from a generic config and applies `structuredExtraConfig`.
        # To use a defconfig directly, you'd modify how `buildLinux` is called or
        # ensure your `structuredExtraConfig` is comprehensive enough.
      }
    );

  # Build the kernel package itself
  customKernel = pkgs.callPackage linux_patched {
    # You can pass additional arguments to linux_patched here if needed,
    # for example, if you need to override stdenv or other build inputs.
  };

  # Create the corresponding linuxPackages set (headers, tools, etc.)
  linuxPackages_custom_patched = pkgs.linuxPackagesFor customKernel;

in
{
  # Define the NixOS options for this module
  options.${namespace}.system.patched-kernel = {
    enable = mkEnableOption "a custom patched kernel";

    kernelOwner = mkOption {
      type = types.str;
      default = "torvalds"; # Example: "collabora", "rockchip-linux"
      description = "The GitHub owner (user or organization) of the kernel repository.";
    };

    kernelRepo = mkOption {
      type = types.str;
      default = "linux"; # Example: "linux", "kernel-rockchip"
      description = "The name of the kernel repository on GitHub.";
    };

    kernelRev = mkOption {
      type = types.str;
      default = "master"; # Or a specific tag like "v6.14.0", or a commit SHA
      description = "Git branch, tag, or commit hash of the kernel repository to use.";
    };

    kernelSourceHash = mkOption {
      type = types.str;
      # IMPORTANT: You MUST replace this with the actual prefetch hash.
      # Use lib.fakeSha256 or a placeholder like below initially.
      # nix-build will fail and tell you the correct hash.
      default = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # REPLACE THIS
      description = "SHA256 hash of the fetched kernel source code (replace after first failed build).";
      example = "sha256-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG=";
    };

    extraPatches = mkOption {
      type = types.listOf types.path; # A patch can be a local file path or a derivation (e.g., from fetchpatch)
      default = [];
      description = ''
        A list of additional patches to apply to the kernel source.
        Patches are applied in the order they are listed.
      '';
      example = literalExpression ''
        [
          (pkgs.fetchpatch {
            name = "0001-rockchip-gic-fix.patch";
            url = "https://example.com/path/to/your/rockchip-gic-fix.patch";
            hash = "sha256-patchhashhere";
            # Apply arguments if the patch needs it, e.g., stripLen = 1;
          })
          ./my-local-board-quirk.patch  # Assuming this patch is next to your configuration.nix
        ]
      '';
    };

    debug = mkOption {
      type = types.bool;
      default = false; # Set to true to enable kernel debug options
      description = "Enable kernel debug features (DEBUG_KERNEL, DEBUG_INFO, etc.).";
    };
  };

  # Apply the configuration if this module is enabled
  config = mkIf cfg.enable {
    # Set the system to use the custom patched kernel and its packages
    boot.kernelPackages = mkForce linuxPackages_custom_patched;

    # If you were using bcachefs and no longer need it with this kernel,
    # you might want to remove it from supportedFilesystems and systemPackages.
    # boot.supportedFilesystems = lib.mkIf (builtins.elem "bcachefs" config.boot.supportedFilesystems)
    #   (lib.filter (fs: fs != "bcachefs") config.boot.supportedFilesystems)
    #   else config.boot.supportedFilesystems; # Or just let it be if not harmful

    # environment.systemPackages = lib.mkIf (builtins.any (p: p.pname == "bcachefs-tools") config.environment.systemPackages)
    #   (lib.filter (p: p.pname != "bcachefs-tools") config.environment.systemPackages)
    #   else config.environment.systemPackages;
    # Consider if perf tools from the custom kernel are needed:
    # environment.systemPackages = with pkgs; [ linuxPackages_custom_patched.perf ];
  };
}
