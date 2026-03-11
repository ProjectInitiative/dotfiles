# NixOS System Configuration for dcc-ex
# Based on Libre Computer Renegade (RK3328)
#
# To build this system:
# nom build .\#nixosConfigurations.dcc-ex.config.system.build.sdImage

{
  config,
  inputs,
  pkgs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
{
  imports = inputs.nixos-on-arm.bootModules.renegade;

  # Enable JMRI Server from the dcc-ex flake
  services.jmri-server = {
    enable = true;
  };

  # Disable ZFS if it causes issues with latest kernels on this platform
  boot.supportedFilesystems.zfs = lib.mkForce false;

  projectinitiative = {
    settings = {
      stateVersion = lib.mkForce "25.05";
    };

    system = {
      nix-config = enabled;
    };

    suites = {
      development = enabled;
    };

    networking = {
      tailscale = {
        enable = true;
      };
    };
  };

  # Host identification
  networking = {
    hostName = "dcc-ex";
    useDHCP = true;
  };

  system.stateVersion = lib.mkForce "25.05";

  # Remote access
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  environment.systemPackages = with pkgs; [
    avrdude # For flashing Arduino Mega
    minicom # For serial debugging
    python3
    gnumake
  ];
}
