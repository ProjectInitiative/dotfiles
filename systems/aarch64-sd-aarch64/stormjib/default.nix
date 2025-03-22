# the masthead routers will be named accordingly:
# Topsail (Primary) & StormJib (Backup)
#     Topsail: Agile sail for fair-weather speed (primary performance).
#     StormJib: Rugged sail for heavy weather (backup resilience).

{ pkgs, ... }:
{
  config = {
    projectinitiative = {
      hosts.masthead.stormjib.enable = false;
      networking = {
        tailscale.enable = true;
      };
    };

    # Raspberry Pi specific settings
    hardware.raspberry-pi."4".apply-overlays-dtmerge.enable = true;
    hardware.deviceTree.enable = true;
    
    # Include essential Pi firmware
    hardware.firmware = [ pkgs.raspberrypiWirelessFirmware ];
    
    # Boot settings for Raspberry Pi
    boot = {
      kernelPackages = pkgs.linuxPackages_rpi4;
      initrd.availableKernelModules = [ "usbhid" "usb_storage" ];
      loader = {
        grub.enable = false;
        generic-extlinux-compatible.enable = true;
      };
    };

    services.openssh.enable = true;
  };
}
