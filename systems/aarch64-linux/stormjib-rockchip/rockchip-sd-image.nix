{ config, lib, pkgs, modulesPath, ... }:

let
  # Use a specific Linux kernel package if needed
  customKernel = pkgs.linuxPackages_latest;
  # Or target a specific version like this:
  # customKernel = pkgs.linuxPackages_6_14;
in
{
  imports = [
    (modulesPath + "/profiles/base.nix")
    (modulesPath + "/installer/sd-card/sd-image.nix")
  ];
  
  sdImage = {
    firmwareSize = 32; # MB
    compressImage = false;
    expandOnBoot = false;
    
    populateFirmwareCommands = ''
      # Create the firmware directory
      mkdir -p firmware
      
      # Let's verify the DTB file exists before copying
      # This will show all available DTB files for Rockchip
      find ${customKernel.kernel}/dtbs/rockchip -type f -name "*.dtb" || true
      
      # Copy our specific DTB file - use a conditional to prevent failure
      if [ -f ${customKernel.kernel}/dtbs/rockchip/rk3582-radxa-e52c.dtb ]; then
        cp ${customKernel.kernel}/dtbs/rockchip/rk3582-radxa-e52c.dtb firmware/
      else
        echo "DTB file not found! Build will continue but the image may not boot."
        # You might want to list available DTBs here to help find the right one
        find ${customKernel.kernel}/dtbs/rockchip -name "*.dtb" | sort
      fi
      
      # Set up extlinux configuration for Rockchip
      mkdir -p firmware/extlinux
      cat > firmware/extlinux/extlinux.conf << EOF
      DEFAULT nixos
      MENU TITLE Rockchip Boot Options
      TIMEOUT 10
      LABEL nixos
        KERNEL /nixos/$(basename ${config.system.build.kernel})/Image
        INITRD /nixos/$(basename ${config.system.build.initialRamdisk})/initrd
        FDT /nixos/$(basename ${customKernel.kernel})/dtbs/rockchip/rk3582-radxa-e52c.dtb
        APPEND init=${config.system.build.toplevel}/init console=ttyFIQ0,1500000n8 console=tty1 earlycon=uart8250,mmio32,0xff1a0000 loglevel=7
      EOF
    '';
    
    populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
    '';
  };
  
  boot = {
    loader.grub.enable = false;
    loader.generic-extlinux-compatible.enable = true;
    consoleLogLevel = 7;
    
    # Use the custom kernel package
    kernelPackages = customKernel;
    
    kernelParams = [
      "console=ttyFIQ0,1500000n8"
      "console=tty1"
      "earlycon=uart8250,mmio32,0xff1a0000" 
      "loglevel=7"
      "debug"
      # Add these from Debian:
      "coherent_pool=2M"
      "irqchip.gicv3_pseudo_nmi=0"
      # other options
      "ignore_loglevel"
      "initcall_debug"  # Shows all init calls
      "earlyprintk"     # Earlier kernel messages
      "keep_bootcon"    # Keep boot console
    ];
    
  };
  
  hardware.deviceTree = {
    enable = true;
    name = "rockchip/rk3582-radxa-e52c.dtb";
  };
  
  environment.systemPackages = with pkgs; [
    coreutils
    util-linux
    iproute2
  ];
  
  services.xserver.enable = false;
  documentation.enable = false;
  hardware.pulseaudio.enable = false;
  
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes"; # For initial debugging only
  };
}
