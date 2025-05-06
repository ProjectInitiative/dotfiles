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

  # Define the custom kernel package here
  linux_bcachefs =
    { fetchFromGitHub, buildLinux, ... }@args:
    buildLinux (
      args
      // rec {
        version = "6.15.0-rc4-bcachefs";
        modDirVersion = "6.15.0-rc4";

        src = fetchFromGitHub {
          owner = "koverstreet";
          repo = "bcachefs";
          rev = cfg.rev;
          hash = cfg.hash;
        };

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

  # Build the kernel package directly
  customKernel = pkgs.callPackage linux_bcachefs { };

  # Create the linuxPackages for our custom kernel
  linuxPackages_custom_bcachefs = pkgs.linuxPackagesFor customKernel;

in
{
  options.${namespace}.system.bcachefs-kernel = {
    enable = mkEnableOption "custom bcachefs kernel with read_fua_test support";

    rev = mkOption {
      type = types.str;
      default = "master";
      description = "Git branch or commit hash of Kent Overstreet's bcachefs repository to use";
    };

    hash = mkOption {
      type = types.str;
      default = "sha256:0000000000000000000000000000000000000000000000000000";
      description = "SHA256 hash of the source code (replace after first build attempt)";
    };

    debug = mkOption {
      type = types.bool;
      default = true;
      description = "Enable bcachefs debug features";
    };
  };

  config = mkIf cfg.enable {
    # nixpkgs.overlays = [
    #   (final: prev: {
    #     linuxPackages_custom_bcachefs =
    #       let
    #         linux_bcachefs = { fetchFromGitHub, buildLinux, ... } @ args:
    #           buildLinux (args // rec {
    #             version = "6.12-bcachefs";
    #             modDirVersion = "6.12.0";

    #             src = fetchFromGitHub {
    #               owner = "koverstreet";
    #               repo = "bcachefs";
    #               rev = cfg.branch;
    #               sha256 = cfg.sourceHash;
    #             };

    #             structuredExtraConfig = with lib.kernel; {
    #               BCACHEFS_FS = yes;
    #               BCACHEFS_QUOTA = yes;
    #               BCACHEFS_POSIX_ACL = yes;
    #             } // (if cfg.debug then {
    #               BCACHEFS_DEBUG = yes;
    #               BCACHEFS_TESTS = yes;
    #             } else {});
    #           });
    #       in
    #       final.linuxPackagesFor (final.callPackage linux_bcachefs {});
    #   })
    # ];

    # Use the custom kernel
    boot.kernelPackages = mkForce linuxPackages_custom_bcachefs;

    # Ensure bcachefs support is enabled
    boot.supportedFilesystems = [ "bcachefs" ];

    # Install bcachefs tools and our test script
    environment.systemPackages = with pkgs; [
      bcachefs-tools
      linuxPackages_custom_bcachefs.perf
    ];

  };
}
