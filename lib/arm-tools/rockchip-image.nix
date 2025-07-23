{ config, lib, pkgs, modulesPath, ... }:

with lib;

let
  cfg = config.rockchip;
  ubootPackage = cfg.uboot.package;
  # Import the fixed assembler module
  assembleMonolithicImage = import ./assemble-monolithic-image.nix;
in
{
  imports = [
    (modulesPath + "/profiles/base.nix")
  ];

  ###### Interface ######
  options = {
    rockchip = {
      enable = mkEnableOption "Rockchip SoC support";
      uboot.package = mkOption {
        type = types.package;
        description = "The U-Boot package providing idbloader.img and u-boot.itb.";
      };
      image = {
        name = mkOption { type = types.str; default = "nixos-rockchip"; };
        imagePaddingMB = mkOption { type = types.int; default = 100; };
        fullImageBootOffsetMB = mkOption { type = types.int; default = 16; };
        osImageBootOffsetMB = mkOption { type = types.int; default = 1; };
        buildVariants = {
          full = mkOption { type = types.bool; default = true; description = "Build full eMMC-style image with U-Boot."; };
          sdcard = mkOption { type = types.bool; default = false; description = "Build OS-only image for SD cards (no U-Boot)."; };
          ubootOnly = mkOption { type = types.bool; default = false; description = "Build a minimal image containing only U-Boot."; };
        };
      };
      deviceTree = mkOption { type = types.nullOr types.str; default = null; };
      console = {
        earlycon = mkOption { type = types.nullOr types.str; default = null; };
        console = mkOption { type = types.nullOr types.str; default = null; };
      };
    };
  };

  ###### Implementation ######
  config = mkIf cfg.enable {
    # A. Configure UKI boot
    boot.kernelPackages = pkgs.linuxPackages_latest;
    boot.loader.systemd-boot.enable = true;
    boot.loader.grub.enable = false;
    hardware.firmware = with pkgs; [ firmwareLinuxNonfree ];

    hardware.deviceTree = mkIf (cfg.deviceTree != null) {
      enable = true;
      name = cfg.deviceTree;
    };

    # B. Build partition images
    system.build.nixosBootPartitionImage = pkgs.callPackage ./make-fat-fs.nix {
      volumeLabel = "NIXOS_BOOT";
      size = "256M";
      populateImageCommands = ''
        mkdir -p ./files/EFI/BOOT
        cp ${config.system.build.uki}/${config.system.boot.loader.ukiFile} ./files/EFI/BOOT/BOOTAA64.EFI
      '';
      storePaths = [ ];
    };

    system.build.nixosRootfsPartitionImage = pkgs.callPackage "${pkgs.path}/nixos/lib/make-ext4-fs.nix" {
      storePaths = [ config.system.build.toplevel ];
      volumeLabel = "NIXOS_ROOT";
      compressImage = false;
    };

    # C. Assemble the final image
    system.build.rockchipImages = assembleMonolithicImage {
      inherit pkgs lib;
      ubootIdbloaderFile = "${ubootPackage}/idbloader.img";
      ubootItbFile = "${ubootPackage}/u-boot.itb";
      nixosBootImageFile = config.system.build.nixosBootPartitionImage;
      nixosRootfsImageFile = config.system.build.nixosRootfsPartitionImage;
      imageName = cfg.image.name;
      imagePaddingMB = cfg.image.imagePaddingMB;
      fullImageBootOffsetMB = cfg.image.fullImageBootOffsetMB;
      osImageBootOffsetMB = cfg.image.osImageBootOffsetMB;
      buildFullImage = cfg.image.buildVariants.full;
      buildOsImage = cfg.image.buildVariants.sdcard;
      buildUbootImage = cfg.image.buildVariants.ubootOnly;
    };

    # D. Set default build target
    system.build.image = config.system.build.rockchipImages;

    # E. Filesystem configuration
    fileSystems = {
      "/" = { device = "/dev/disk/by-label/NIXOS_ROOT"; fsType = "ext4"; };
      "/boot" = { device = "/dev/disk/by-label/NIXOS_BOOT"; fsType = "vfat"; };
    };

    # F. First boot partition resizing service
    systemd.services.expand-root-fs = {
      description = "Expand Root Partition to Fill Disk";
      after = [ "systemd-remount-fs.service" ];
      wants = [ "systemd-remount-fs.service" ];
      wantedBy = [ "multi-user.target" ];

      unitConfig.ConditionPathExists = "!/etc/nixos-partition-resized";

      script = ''
        set -euo pipefail
        set -x

        rootPart="/dev/disk/by-label/NIXOS_ROOT"

        # Wait up to 10 seconds for the device to appear.
        for i in $(seq 10); do
          [ -b "$rootPart" ] && break
          echo "Waiting for $rootPart..."
          sleep 1
        done

        if ! [ -b "$rootPart" ]; then
          echo "Device $rootPart never appeared!"
          exit 1
        fi

        # Get the actual device path (resolves symlink)
        rootDev=$(${pkgs.coreutils}/bin/readlink -f "$rootPart")
        
        # Extract partition number from device name (e.g., /dev/mmcblk1p2 -> 2)
        partNum=$(echo "$rootDev" | ${pkgs.gnugrep}/bin/grep -o '[0-9]*$')
        
        # Get the parent block device (e.g., /dev/mmcblk1p2 -> /dev/mmcblk1)
        bootDevice=$(echo "$rootDev" | ${pkgs.gnused}/bin/sed 's/p\?[0-9]*$//')

        echo "Root device: $rootDev"
        echo "Boot device: $bootDevice" 
        echo "Partition number: $partNum"

        # Expand the partition
        ${pkgs.cloud-utils}/bin/growpart "$bootDevice" "$partNum"

        # Resize the filesystem to use the new space.
        ${pkgs.e2fsprogs}/bin/resize2fs "$rootDev"
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
        ExecStartPost = "${pkgs.coreutils}/bin/touch /etc/nixos-partition-resized";
        Path = with pkgs; [ coreutils util-linux parted e2fsprogs gawk cloud-utils gnugrep gnused ];
      };
    };

    # G. Ensure necessary packages are in the image (iproute2 and cloud-utils are no longer strictly required by the resize logic but might be useful)
    environment.systemPackages = with pkgs; [
      iproute2
      cloud-utils
    ];
  };
}
