{ config, lib, pkgs, namespace, ... }:

with lib;
with lib.${namespace};

let
  cfg = config.${namespace}.system.bcachefs-module;
in
{
  options.${namespace}.system.bcachefs-module = {
    enable = mkBoolOpt false "Whether to enable bcachefs as a kernel module";
    
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

    # repo = mkOption { type = types.str; default = ""; description = "Git repo for bcachefs"; };
    rev = mkOption { type = types.str; default = "master"; description = "Git revision for bcachefs"; };
    hash = mkOption { type = types.str; default = lib.fakeSha256; description = "Expected hash for the revision"; };
  };

  config = mkIf cfg.enable {
    # Add the module to the kernel module packages
    boot.extraModulePackages = [ 
      (pkgs.extend (final: super: {
        ${namespace} = pkgs.${namespace} // {
          # 1. Override the kernel input first
          bcachefs-module = super.${namespace}.bcachefs-module.override {
            kernel = config.boot.kernelPackages.kernel;
          }
          # 2. Then override attributes like 'src' using overrideAttrs
          .overrideAttrs (oldAttrs: {
            # Replace the src attribute with a new fetchFromGitHub call
            src = final.fetchFromGitHub { # Use final.fetchFromGitHub from the overlay
              # You need to repeat owner/repo, or potentially get them from oldAttrs.src if reliable
              owner = "koverstreet"; # Or oldAttrs.src.owner
              repo = "bcachefs";    # Or oldAttrs.src.repo
              # Use the new rev and hash
              rev = cfg.rev;
              hash = cfg.hash;
            };

            # Optional but recommended: Update version string to reflect the override
            # This helps avoid nix store path collisions if only the hash changes.
            version = "${oldAttrs.version}-rev-${builtins.substring 0 7 cfg.rev}";
          });
        };
      })).${namespace}.bcachefs-module
    ];
    
    # Automatically load the module if configured
    boot.kernelModules = mkIf cfg.autoload [ "bcachefs" ];
    
    # Ensure bcachefs tools are installed
    environment.systemPackages = with pkgs; [
      bcachefs-tools
    ];
    
    # Ensure filesystem support is enabled
    boot.supportedFilesystems = [ "bcachefs" ];

    # Add helpful boot messages for debug
    boot.postBootCommands = mkIf cfg.debug ''
      echo "Loading bcachefs kernel module..."
      modprobe bcachefs && echo "bcachefs module loaded successfully!" || echo "Failed to load bcachefs module"
      lsmod | grep bcachefs
    '';
  };
}
