# the masthead routers will be named accordingly:
# Topsail (Primary) & StormJib (Backup)
#     Topsail: Agile sail for fair-weather speed (primary performance).
#     StormJib: Rugged sail for heavy weather (backup resilience).

{
  options,
  config,
  lib,
  pkgs,
  namespace,
  modulesPath,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.stormjib;
  sops = config.sops;
in
{

  imports = [
  ];

  config = {

    # boot.loader.grub.enable = true;
    # boot.loader.grub.devices = mkDefault [ "/dev/vda" ]; # nodev for efi
    # fileSystems."/" = mkDefault {
    #   device = "/dev/disk/by-label/nixos";
    #   fsType = "ext4";
    # };

    # Basic system configuration
    system.stateVersion = "23.11";

    # Enable displaying network info on console
    projectinitiative = {
      system = {
        console-info = {
          ip-display = enabled;
        };
      };
    };

    networking.networkmanager.enable = true;

    # Add your other configuration options here
    services.openssh.enable = true;
    # programs.zsh.enable = true;
  };
}
