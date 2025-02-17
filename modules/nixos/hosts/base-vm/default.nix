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
  sops = config.sops;
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
    fileSystems."/" = mkDefault {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };
    disko.devices = {
      disk = {
        one = {
          type = "disk";
          device = "/dev/vda";
          content = {
            type = "gpt";
            partitions = {
              boot = {
                size = "500M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "umask=0077" ];
                };
              };
              primary = {
                size = "100%";
                content = {
                  type = "lvm_pv";
                  vg = "pool";
                };
              };
            };
          };
        };
      };
      lvm_vg = {
        pool = {
          type = "lvm_vg";
          lvs = {
            root = {
              size = "100%FREE";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = [
                  "defaults"
                ];
              };
            };
            # home = {
            #   size = "100%FREE";
            #   content = {
            #     type = "filesystem";
            #     format = "ext4";
            #     mountpoint = "/home";
            #   };
            # };
          };
        };
      };
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
