# the masthead routers will be named accordingly:
# Topsail (Primary) & StormJib (Backup)
#     Topsail: Agile sail for fair-weather speed (primary performance).
#     StormJib: Rugged sail for heavy weather (backup resilience).

{ pkgs, ... }:
{
  config = {

    # imports = [
    #   <nixos-hardware/raspberry-pi/4>
    # ];

    sdImage.compressImage = false;

    projectinitiative = {
      hosts.masthead.stormjib.enable = false;
      networking = {
        tailscale.enable = true;
      };
    };

    # hardware = {
    #   raspberry-pi."4".apply-overlays-dtmerge.enable = true;
    #   deviceTree = {
    #     enable = true;
    #     filter = "*rpi-4-*.dtb";
    #   };
    # };
    console.enable = true;
    environment.systemPackages = with pkgs; [
      libraspberrypi
      raspberrypi-eeprom
    ];

    # Basic networking
    networking.networkmanager.enable = true;
    # Prevent host becoming unreachable on wifi after some time.
    networking.networkmanager.wifi.powersave = false;

    # Raspberry Pi specific settings
    # hardware.deviceTree.enable = true;

    # Include essential Pi firmware
    # hardware.firmware = [ pkgs.raspberrypiWirelessFirmware ];

    # Boot settings for Raspberry Pi
    # boot = {
    #   kernelPackages = pkgs.linuxPackages_rpi4;
    #   initrd.availableKernelModules = [ "usbhid" "usb_storage" ];
    #   loader = {
    #     grub.enable = false;
    #     generic-extlinux-compatible.enable = true;
    #   };
    # };

    # users.users.kylepzak.initialPassword = "changeme";
    # users.users.root.initialPassword = "changeme";
    services = {
      openssh = {
        enable = true;
        hostKeys = [
          {
            path = "/etc/ssh/ssh_host_ed25519_key";
            type = "ed25519";
            source = "./id_ed25519";
            publicKeySource = "./id_ed25519.pub";
          }
        ];
      };
    };
  };
}
