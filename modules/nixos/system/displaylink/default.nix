{
  lib,
  config,
  pkgs,
  inputs,
  namespace,
  ...
}:

with lib;

let
  cfg = config.${namespace}.system.displaylink;
in
{
  options.${namespace}.system.displaylink = {
    enable = mkEnableOption "Custom DisplayLink and EVDI setup using an EVDI source from an unstable Nixpkgs input";

    evdiUnstableAttributePath = mkOption {
      type = types.str;
      # Example: "linuxPackages_latest.evdi" or "linuxPackages.evdi"
      # The default should be what's most common in nixpkgs-unstable for evdi.
      default = "linuxPackages_latest.evdi";
      description = ''
        Attribute path for the desired EVDI package source within the unstable Nixpkgs input's
        legacyPackages for the current system (e.g., "linuxPackages_latest.evdi",
        "linuxPackages.evdi", "linuxPackages_xanmod_latest.evdi").
        This EVDI source will be built against the system's active kernel
        (config.boot.kernelPackages.kernel).
      '';
    };

    displaylinkArchive = mkOption {
      type = types.submodule {
        options = {
          url = mkOption {
            type = types.str;
            default = "https://www.synaptics.com/sites/default/files/exe_files/2025-04/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.1.1-EXE.zip";
            description = "URL for the DisplayLink software archive.";
          };
          sha256 = mkOption {
            type = types.str;
            # IMPORTANT: Ensure this hash matches the URL content.
            # The value "sha256-yiIw6UDOLV1LujxhAVsfjIA5he++8W022+EK/OZTwXI=" is for DisplayLink Ubuntu 6.1.1-EXE.zip
            default = "sha256-yiIw6UDOLV1LujxhAVsfjIA5he++8W022+EK/OZTwXI=";
            description = "SHA256 hash of the DisplayLink software archive.";
          };
          packageVersion = mkOption {
            type = types.str;
            default = "6.1.1-17"; # This should match the version inside the DisplayLink .run script in the archive
            description = "Version string for the DisplayLink package.";
          };
        };
      };
      description = "Configuration for fetching the DisplayLink proprietary driver.";
      default = { };
    };
    kernel = mkOption {
      type = types.package;
      default = config.boot.kernelPackages.kernel;
    };
  };

  config = mkIf cfg.enable (
    let
      # Attempt to access inputs.unstable.legacyPackages.<system>
      # Provides null if any part of the path is missing.
      unstablePkgsForSystem = lib.attrByPath [
        "unstable"
        "legacyPackages"
        config.nixpkgs.system
      ] null inputs;

      # The kernel your system is currently configured to use.
      # kernelToBuildAgainst = config.boot.kernelPackages.kernel;
      kernelToBuildAgainst = cfg.kernel;

      evdiSourcePathParts = lib.splitString "." cfg.evdiUnstableAttributePath;

      # This is the EVDI package *from the unstable Nixpkgs input*.
      # It's likely built against a kernel from that unstable input.
      evdiSourceFromUnstable =
        if unstablePkgsForSystem != null then
          lib.attrByPath evdiSourcePathParts null unstablePkgsForSystem
        else
          null;

      # This attempts to take the evdiSourceFromUnstable and override it
      # to be built against your system's actual kernel.
      # evdiBuiltForSystemKernel =
      #   if evdiSourceFromUnstable != null && lib.isDerivation evdiSourceFromUnstable then
      #     evdiSourceFromUnstable.override {
      #       kernel = kernelToBuildAgainst;
      #       # Depending on the evdi package structure, you might sometimes need:
      #       # kernelPackages = config.boot.kernelPackages;
      #     }
      #   else
      #     null;
      evdiBuiltForSystemKernel =
        if evdiSourceFromUnstable != null && lib.isDerivation evdiSourceFromUnstable then
          evdiSourceFromUnstable.overrideAttrs (oldAttrs: {
            # Ensure nativeBuildInputs from the original evdi are preserved,
            # and add pkg-config if it's missing.
            # Also add common tools for kernel module builds.
            nativeBuildInputs =
              (oldAttrs.nativeBuildInputs or [ ])
              ++ (with pkgs; [
                pkg-config # Explicitly add pkg-config
                kmod # For depmod, etc.
                # Add other tools if the build complains about them later
              ]);

            # This is crucial for kernel module builds:
            # It ensures the build uses the development headers and scripts from the target kernel.
            # The original evdi package in Nixpkgs likely sets this up correctly via stdenv.mkDerivation's
            # special handling for kernel modules, but an override might need it explicitly.
            # We are passing the full kernel package set here, as some modules expect it.
            # The 'kernel' attribute within this set will be what we want.
            kernel = kernelToBuildAgainst; # This should point to the derivation of kernelToBuildAgainst itself.

            # If the EVDI package specifically expects kernel_dev or similar in its override,
            # you might need to inspect its original derivation in nixpkgs-unstable.
            # However, just passing the kernel derivation (which includes .dev output)
            # is often enough when stdenv.mkDerivation handles it.

            # Sometimes, explicitly setting the kernel build directory helps
            # KERNEL_BUILD_DIR = "${kernelToBuildAgainst.dev}/lib/modules/${kernelToBuildAgainst.modDirVersion}/build";
            # And the source directory
            # KERNEL_SRC_DIR = "${kernelToBuildAgainst.dev}/lib/modules/${kernelToBuildAgainst.modDirVersion}/source";

            # If the build is still trying to write to the source directory,
            # it might be that the Makefile needs patching or specific environment variables
            # to tell it where to put temporary files. This is harder to fix without
            # diving into the EVDI Makefile.

            # Let's try to ensure the build happens in $out, which is writable.
            # The default stdenv.mkDerivation phases usually handle this, but
            # if the Makefile is misbehaving:
            # preBuild = oldAttrs.preBuild or "" + ''
            #   export KBUILD_OUTPUT="$TMPDIR/kbuild_output"
            #   mkdir -p "$KBUILD_OUTPUT"
            #   # or export KBUILD_OUTPUT="$PWD/kbuild_output"; mkdir -p kbuild_output # if it needs to be relative to module source
            # '';

            # The issue might be that the Makefiles are trying to create .tmp_X directories
            # in the kernel build directory, which is read-only.
            # This often means the kernel's build system isn't being invoked in a way
            # that it understands it needs to place temporary files elsewhere.
          })
        else
          null;

      customDisplaylinkPackage =
        if evdiBuiltForSystemKernel != null then
          (pkgs.displaylink.override {
            # IMPORTANT: Use displaylink from your system's `pkgs`
            evdi = evdiBuiltForSystemKernel;
            requireFile =
              _:
              pkgs.fetchurl {
                url = cfg.displaylinkArchive.url;
                # The name for fetchurl is mostly for nix store path readability
                name = "displaylink-archive-${cfg.displaylinkArchive.packageVersion}.zip";
                sha256 = cfg.displaylinkArchive.sha256;
              };
          }).overrideAttrs
            (oldAttrs: {
              __intentionallyOverridingVersion = true;
              version = cfg.displaylinkArchive.packageVersion;
              # pname = oldAttrs.pname; # Usually not needed, but good to be aware of
            })
        else
          null;

    in
    {
      assertions = [
        {
          assertion = unstablePkgsForSystem != null;
          message = ''
            [${namespace}.system.displaylink] ASSERTION FAILED: Could not correctly access the unstable package set for system "${config.nixpkgs.system}".
            Path 'inputs.unstable.legacyPackages.${config.nixpkgs.system}' was not found or is not an attrset.
            Please ensure:
            1. You have an input named 'unstable' in your flake.nix that points to a Nixpkgs source (e.g., nixpkgs/nixos-unstable).
            2. This 'unstable' input provides 'legacyPackages'.
            3. 'legacyPackages' has an attribute for your system: '${config.nixpkgs.system}'.

            DEBUG INFO:
            - inputs ? "unstable": ${toString (inputs ? "unstable")}
            - inputs.unstable ? "legacyPackages" (if inputs.unstable exists): ${
              if inputs ? "unstable" then toString (inputs.unstable ? "legacyPackages") else "N/A"
            }
            - Type of inputs.unstable.legacyPackages (if exists): ${
              if inputs ? "unstable" && inputs.unstable ? "legacyPackages" then
                builtins.typeOf inputs.unstable.legacyPackages
              else
                "N/A"
            }
            - inputs.unstable.legacyPackages ? "${config.nixpkgs.system}" (if parent attrs exist and are attrsets): ${
              let
                u = inputs.unstable or { };
                lp = u.legacyPackages or { };
              in
              if builtins.isAttrs lp then
                toString (lp ? config.nixpkgs.system)
              else
                "N/A (inputs.unstable.legacyPackages not an attrset or not found)"
            }
            - Type of inputs.unstable.legacyPackages."${config.nixpkgs.system}" (if key exists and parents are attrsets): ${
              let
                u = inputs.unstable or { };
                lp = u.legacyPackages or { };
                sysKey = config.nixpkgs.system;
                s = if builtins.isAttrs lp && (lp ? sysKey) then lp.${sysKey} else null;
              in
              if s != null then builtins.typeOf s else "N/A"
            }
          '';
        }
        {
          assertion = evdiSourceFromUnstable != null && lib.isDerivation evdiSourceFromUnstable;
          message = ''
            [${namespace}.system.displaylink] ASSERTION FAILED: The 'evdiUnstableAttributePath' ('${cfg.evdiUnstableAttributePath}')
            does not point to a valid derivation in 'inputs.unstable.legacyPackages.${config.nixpkgs.system}'.
            Value resolved for evdiSourceFromUnstable: ${toString evdiSourceFromUnstable}
            (This might be null if unstablePkgsForSystem was null, or if the path was incorrect).
          '';
        }
        {
          # This assertion checks if the override step itself was initiated.
          # It doesn't guarantee the resulting package will build successfully,
          # but it checks that the input to the override was valid.
          assertion = evdiBuiltForSystemKernel != null;
          message = ''
            [${namespace}.system.displaylink] ASSERTION FAILED: Failed to prepare 'evdiBuiltForSystemKernel'.
            This usually means 'evdiSourceFromUnstable' was null or not a derivation.
            Please check the previous assertion messages.
          '';
        }
        {
          assertion = customDisplaylinkPackage != null;
          message = ''
            [${namespace}.system.displaylink] ASSERTION FAILED: Failed to prepare 'customDisplaylinkPackage'.
            This usually means 'evdiBuiltForSystemKernel' was null (could not be prepared).
            Please check the previous assertion messages.
          '';
        }
      ];

      # This module does NOT override config.boot.kernelPackages by default.
      # It uses the kernel already configured for the system.

      # Add the EVDI module compiled against the system kernel.
      # boot.extraModulePackages = mkIf (evdiBuiltForSystemKernel != null) [ evdiBuiltForSystemKernel ];

      # Ensure the evdi kernel module is loaded.
      boot.kernelModules = mkIf (evdiBuiltForSystemKernel != null) [ "evdi" ];
      # boot.kernelModules = mkIf (evdiBuiltForSystemKernel != null) [ "evdi" ];

      # Install the custom DisplayLink userspace package.
      environment.systemPackages = mkIf (customDisplaylinkPackage != null) [ customDisplaylinkPackage ];

      # Standard Xorg driver for DisplayLink.
      services.xserver.videoDrivers = [
        "displaylink"
        "modesetting"
      ];
    }
  );
}
