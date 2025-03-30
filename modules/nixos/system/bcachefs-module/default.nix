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
  };

  config = mkIf cfg.enable {
    # Add the module to the kernel module packages
    boot.extraModulePackages = [ 
      (pkgs.extend (_: _: {
        ${namespace} = pkgs.${namespace} // {
          bcachefs-module = pkgs.${namespace}.bcachefs-module.override {
            kernel = config.boot.kernelPackages.kernel;
          };
        };
      })).${namespace}.bcachefs-module
    ];
    
    # Automatically load the module if configured
    boot.kernelModules = mkIf cfg.autoload [ "bcachefs" ];
    
    # Ensure bcachefs tools are installed
    environment.systemPackages = with pkgs; [
      bcachefs-tools
      nvme-cli  # For gathering NVMe device info
    ] ++ optionals (config.${namespace}.packages.bcachefs-fua-test.enable or false) [
      pkgs.${namespace}.bcachefs-fua-test
    ] ++ optionals (config.${namespace}.packages.bcachefs-io-metrics.enable or false) [
      pkgs.${namespace}.bcachefs-io-metrics
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
