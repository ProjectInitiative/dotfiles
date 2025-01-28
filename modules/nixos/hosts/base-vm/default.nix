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
  cfg = config.${namespace}.hosts.base-vm;
in
{
  options.${namespace}.hosts.base-vm = with types; {
    enable = mkBoolOpt false "Whether or not to enable the virtual machine base config.";
  };

  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  config = mkIf cfg.enable {

    boot.loader.grub.enable = true;
    boot.loader.grub.devices = mkDefault [ "/dev/vda" ]; # nodev for efi
    fileSystems."/" = {
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
    users.users.root.password = "changeme"; # Remember to change this
    programs.zsh.enable = true;
  };
}
