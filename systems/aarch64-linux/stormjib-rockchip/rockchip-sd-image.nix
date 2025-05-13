# rockchip-sd-image.nix (Refactored for separate /boot partition and monolithic assembly)
{
  config,
  lib,
  pkgs,
  modulesPath, # Used for /profiles/base.nix
  ...
}:

with lib;

let
  # === U-Boot Configuration ===
  ubootBuilds = import ./uboot-build.nix { inherit pkgs; };
  ubootIdbloaderFile = "${ubootBuilds.uboot-rk3588}/bin/idbloader.img";
  ubootItbFile = "${ubootBuilds.uboot-rk3588}/bin/u-boot.itb";

  # === Kernel and Device Tree Configuration ===
  customKernel = pkgs.linuxPackages_6_14; # Example
  dtbName = "rk3582-radxa-e52c.dtb";      # Example
  dtbPath = "rockchip/${dtbName}";        # Example

  # === Partition Labels ===
  bootVolumeLabel = "NIXOS_BOOT";
  rootVolumeLabel = "NIXOS_ROOT"; # Keep consistent for kernel cmdline and rootfs definition

  # === Helper Derivation for Empty /boot Mountpoint ===
  emptyBootDir = pkgs.runCommand "empty-boot-dir" {} ''
    mkdir -p $out/boot
  '';

in
{
  imports = [
    (modulesPath + "/profiles/base.nix") # Common base settings for NixOS
    # REMOVED: (modulesPath + "/installer/sd-card/sd-image.nix")
  ];

  # === NixOS Configuration relevant to the image content ===
  config = {
    # 1. Configure NixOS Bootloader (extlinux) and Filesystems
    boot.loader.generic-extlinux-compatible.enable = true;
    boot.loader.grub.enable = false; # Disable GRUB

    # Kernel, DTB, and kernel parameters
    boot.kernelPackages = customKernel;
    hardware.deviceTree = {
      enable = true;
      name = dtbPath; # Tells NixOS which DTB to use (relative to kernel's dtbs dir)
    };
    boot.kernelParams = [
      "console=ttyFIQ0,115200n8" # Adjust console as needed
      "console=ttyS2,115200n8"
      "earlycon=uart8250,mmio32,0xfeb50000"
      "rootwait"
      # Use the label defined for the root partition
      "root=/dev/disk/by-label/${rootVolumeLabel}"
      "rw"
      "ignore_loglevel"
      "debug"
      "earlyprintk"
    ];

    # Define the filesystems for the running system
    fileSystems."/" = {
      device = "/dev/disk/by-label/${rootVolumeLabel}"; # Must match rootfs volumeLabel
      fsType = "ext4";
    };
    fileSystems."/boot" = {
      device = "/dev/disk/by-label/${bootVolumeLabel}"; # Must match boot volumeLabel
      fsType = "vfat";
    };

    # Include necessary modules in initrd
    boot.initrd.availableKernelModules = [
      "usbhid" "usb_storage" "sd_mod" "mmc_block" "dw_mmc_rockchip" "ext4" "vfat" "nls_cp437" "nls_iso8859-1"
      # Add other essential modules from your previous config if needed
    ];

    # 2. Build the NixOS Boot Partition Image (VFAT)
    system.build.nixosBootPartitionImage = pkgs.callPackage ./make-fat-fs.nix {
      # name = "nixos-boot-partition"; # Optional internal name
      # We don't need the full system closure here, just the boot files.
      # populateImageCommands will copy the required files.
      storePaths = [];
      populateImageCommands = ''
        echo "[INFO] Populating /boot VFAT image..."
        # Create root directory for populateCmd (assuming make-fat-fs expects ./files)
        mkdir -p ./files
        # populateCmd copies kernel, initrd, DTB to ./files/
        # and creates ./files/extlinux/extlinux.conf
        # Use '-c' to specify the system top-level for finding boot files
        # Use '-d' to specify the destination *within the VFAT image build env*
        ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files
        echo "[INFO] /boot VFAT image populated."
      '';
      volumeLabel = bootVolumeLabel; # Filesystem label for the VFAT partition
      size = "256M"; # Define a suitable fixed size for the boot partition
      # uuid = "your-boot-uuid-if-needed"; # Optional
      compressImage = false; # Need raw .img for assembler
    };

    # 3. Build the NixOS Root Filesystem Partition Image (EXT4)
    system.build.nixosRootfsPartitionImage = pkgs.callPackage "${pkgs.path}/nixos/lib/make-ext4-fs.nix" {
      # name = "nixos-rootfs-partition"; # Optional internal name
      storePaths = config.system.build.toplevel; # Include the whole system closure
      volumeLabel = rootVolumeLabel; # Filesystem label for the ext4 partition
      # uuid = "your-root-uuid-if-needed"; # Optional
      # size = "2G"; # Optional: Max size. If not set, fits contents. Resize on boot handles expansion.
      compressImage = false; # Need raw .img for assembler
    };

    # 4. Assemble the Final Monolithic Disk Image(s)
    system.build.finalDiskImages = pkgs.callPackage ./assemble-monolithic-image.nix {
      inherit ubootIdbloaderFile ubootItbFile;
      nixosBootImageFile = config.system.build.nixosBootPartitionImage; # Pass the VFAT image
      nixosRootfsImageFile = config.system.build.nixosRootfsPartitionImage; # Pass the EXT4 image

      # --- Control which images get built by the assembler ---
      buildFullImage = true;  # e.g., Build the U-Boot + Boot Part + Rootfs Part image
      buildUbootImage = true; # e.g., Build the U-Boot only image
      buildOsImage = true;    # e.g., Build the Boot Part + Rootfs Part image (for SD)
    };

    # Point the default system build output to the *directory* containing all assembled images.
    # Or, if you prefer one specific image, adjust accordingly.
    system.build.image = config.system.build.finalDiskImages;
    # Example for Flakes output structure targeting the full image specifically:
    # outputs.packages.${system}.nixos-image = config.system.build.finalDiskImages; # Adjust attr path as needed

    # Post-boot commands for resizing the root partition (remains crucial)
    # This script runs on the *target device* after it boots your image.
    # It only needs to resize the root partition.
    boot.postBootCommands = lib.mkBefore ''
      # On the first boot do some maintenance tasks
      if [ -f /nix-path-registration ]; then
        set -euo pipefail
        set -x

        rootPartDev=$(${pkgs.util-linux}/bin/findmnt -n -o SOURCE /)
        bootDevice=$(${pkgs.util-linux}/bin/lsblk -npo PKNAME "$rootPartDev")
        # Extract partition number robustly (handles /dev/mmcblkXpY and /dev/sdXY)
        partNum=$(echo "$rootPartDev" | sed -E 's|^.*[^0-9]([0-9]+)$|\1|')

        echo "Root partition device: ''${rootPartDev}, Boot device: ''${bootDevice}, Root Partition number: ''${partNum}"

        # Attempt to resize the root partition using growpart or fallback to sfdisk
        # Note: sfdisk resize might be less reliable than growpart
        if command -v growpart > /dev/null && [ -x "$(command -v growpart)" ]; then
          echo "Attempting resize with growpart..."
          ${pkgs.cloud-utils}/bin/growpart "''${bootDevice}" "''${partNum}" || \
            { echo "[WARNING] growpart failed, attempting sfdisk as fallback..."; echo ",+," | sfdisk -N"''${partNum}" --no-reread "''${bootDevice}"; }
        else
          echo "growpart not found, using sfdisk..."
          # sfdisk resize: ',+,' tells it to extend the partition identified by -N to the end
          echo ",+," | sfdisk -N"''${partNum}" --no-reread "''${bootDevice}"
        fi

        echo "Running partprobe on ''${bootDevice}..."
        ${pkgs.parted}/bin/partprobe "''${bootDevice}" || echo "[WARNING] partprobe on ''${bootDevice} encountered an issue."
        sleep 3 # Give kernel time to recognize changes

        echo "Resizing filesystem on ''${rootPartDev}..."
        ${pkgs.e2fsprogs}/bin/resize2fs "''${rootPartDev}"

        echo "Registering Nix paths..."
        ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration
        # touch /etc/NIXOS # Already handled by NixOS activation
        echo "Setting up system profile..."
        ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
        echo "Cleaning up first-boot flag..."
        rm -f /nix-path-registration
        sync
        echo "First boot setup complete."
        set +x
      fi
    '';

    # --- Keep other necessary configurations ---
    hardware.firmware = with pkgs; [ firmwareLinuxNonfree ]; # Example
    environment.systemPackages = with pkgs; [ coreutils util-linux iproute2 parted cloud-utils e2fsprogs emptyBootDir ];
    services.openssh = {
      enable = true;
      settings.PermitRootLogin = "yes"; # For debugging, change for production
    };
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    system.stateVersion = "24.11"; # Or your current version
  };
}
