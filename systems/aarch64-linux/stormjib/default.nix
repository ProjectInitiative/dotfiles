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
  options.${namespace}.hosts.stormjib = with types; {
    enable = mkBoolOpt false "Whether or not to enable the virtual machine base config.";
  };

  imports = [
  ];

  config = mkIf cfg.enable {

    boot.loader.grub.enable = true;
    boot.loader.grub.devices = mkDefault [ "/dev/vda" ]; # nodev for efi
    fileSystems."/" = mkDefault {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };

    services.qemuGuest.enable = true;

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
    users.users.root.hashedPasswordFile = sops.secrets.root_password.path;
    programs.zsh.enable = true;
  };
}
