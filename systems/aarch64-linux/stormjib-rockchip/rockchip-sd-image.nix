# rockchip-sd-image.nix
# Attempts to automate U-Boot binary flashing during image build.
{ config, lib, pkgs, modulesPath, ... }:

let
  # Use a specific Linux kernel package if needed
  customKernel = pkgs.linuxPackages_latest;
  # Or target a specific version like this:
  # customKernel = pkgs.linuxPackages_6_14;

  # Define the DTB filename once
  dtbName = "rk3582-radxa-e52c.dtb";
  dtbPath = "rockchip/${dtbName}";
  fullDtbPath = "${customKernel.kernel}/dtbs/${dtbPath}";

  # Get kernel and initrd paths for easier reference
  kernelImage = "${config.system.build.kernel}/Image";
  initialRamdisk = "${config.system.build.initialRamdisk}/initrd";

  ubootBuilds = import ./uboot-build.nix { inherit pkgs; }; # Assuming crossSystem is defined
  # ubootBuilds = import ./uboot-build.nix { inherit pkgs crossSystem; }; # Assuming crossSystem is defined
  ubootIdbloader = "${ubootBuilds.uboot-rk3588}/bin/idbloader.img";
  ubootItb = "${ubootBuilds.uboot-rk3588}/bin/u-boot.itb";

in
{
  imports = [
    (modulesPath + "/profiles/base.nix")
    (modulesPath + "/installer/sd-card/sd-image.nix")
  ];

  sdImage = {
    # Ensure firmware partition is large enough for kernel, initrd, dtb, extlinux.conf
    firmwareSize = 128; # MB
    compressImage = false;
    expandOnBoot = false; # Handled by postBootCommands

    populateFirmwareCommands = ''
      # Create the firmware directory (should already exist, but ensures it)
      # Note: During build, the firmware partition is mounted at ./firmware
      mkdir -p ./firmware/extlinux

      # --- Copy Boot Files to Firmware Partition ---
      echo "Copying kernel image..."
      cp ${kernelImage} ./firmware/Image || { echo "Failed to copy kernel Image"; exit 1; }

      echo "Copying initial ramdisk..."
      cp ${initialRamdisk} ./firmware/initrd || { echo "Failed to copy initrd"; exit 1; }

      echo "Verifying and copying DTB..."
      if [ -f ${fullDtbPath} ]; then
        cp ${fullDtbPath} ./firmware/${dtbName} || { echo "Failed to copy DTB"; exit 1; }
        echo "DTB copied successfully."
      else
        echo "ERROR: DTB file ${fullDtbPath} not found!"
        echo "Available Rockchip DTBs:"
        find ${customKernel.kernel}/dtbs/rockchip -name "*.dtb" | sort
        exit 1 # Fail the build if DTB is missing
      fi

      # --- Create extlinux.conf ---
      echo "Creating extlinux.conf..."
      cat > ./firmware/extlinux/extlinux.conf << EOF
      DEFAULT nixos
      MENU TITLE Rockchip Boot Options
      TIMEOUT 10
      LABEL nixos
        # Paths are relative to the firmware partition root now
        KERNEL /Image
        INITRD /initrd
        FDT /${dtbName}
        # Keep the APPEND line largely the same, includes kernelParams from boot section
        APPEND init=${config.system.build.toplevel}/init ${lib.concatStringsSep " " config.boot.kernelParams} rw
      EOF
      echo "extlinux.conf created."
    '';

    # This is no longer needed as boot files are on the firmware partition
    populateRootCommands = ''# nothing to do here '';

    # --- Post Build Commands: Flash U-Boot ---
    # This runs *after* the image file ($img) is populated.
    # We use dd to write the fetched U-Boot binaries to the raw image offsets.
    postBuildCommands = ''
      echo "Writing U-Boot idbloader.img to image..."
      # Use conv=notrunc to avoid truncating the image file
      # Use conv=fsync to ensure data is written before continuing
      dd if=${ubootIdbloader} of="$img" seek=64 conv=notrunc,fsync status=progress || \
        { echo "ERROR: Failed to write idbloader.img"; exit 1; }

      echo "Writing U-Boot u-boot.itb to image..."
      dd if=${ubootItb} of="$img" seek=16384 conv=notrunc,fsync status=progress || \
        { echo "ERROR: Failed to write u-boot.itb"; exit 1; }

      echo "U-Boot binaries written."

      # Log partition information for debugging (optional)
      sfdisk -d "$img" || echo "Could not display partition table"
    '';
  };

  boot = {
    loader.grub.enable = false;
    loader.generic-extlinux-compatible.enable = true; # Still needed for config generation
    consoleLogLevel = 7;

    # Use the custom kernel package
    kernelPackages = customKernel;

    kernelParams = [
      # Base console params (also ensure they are in APPEND line in extlinux.conf)
      "console=ttyFIQ0,1500000n8"
      "console=tty1"
      "earlycon=uart8250,mmio32,0xff1a0000"
      "loglevel=7"
      "debug"
      # Add these from Debian/common Rockchip practice:
      "coherent_pool=2M"
      "irqchip.gicv3_pseudo_nmi=0"
      # other debugging options
      "ignore_loglevel"
      "initcall_debug" # Shows all init calls
      "earlyprintk"    # Earlier kernel messages
      "keep_bootcon"   # Keep boot console
      # Add rootwait in case storage takes time to appear
      "rootwait"
      # Ensure root filesystem type is specified if not autodetected reliably
      # "rootfstype=ext4"
    ];

    initrd.availableKernelModules = [
      "usbhid"
      "usb_storage"
      "sd_mod"
      "ehci_platform"
      "ohci_platform"
      "dwc2"
      # Essential Rockchip SD/eMMC modules
      "mmc_block"
      "dw_mmc_rockchip"
      # Filesystem needed for root
      "ext4"
    ];

    # Keep the post-boot commands for resizing partition 2
    postBootCommands = lib.mkBefore ''
      # On the first boot do some maintenance tasks
      if [ -f /nix-path-registration ]; then
        set -euo pipefail
        set -x
        # Figure out device names for the boot device and root filesystem.
        rootPart=$(${pkgs.util-linux}/bin/findmnt -n -o SOURCE /)
        bootDevice=$(lsblk -npo PKNAME "$rootPart")
        # Assuming NixOS standard layout: part 1=firmware, part 2=rootfs
        partNum=2

        # Resize the root partition and the filesystem to fit the disk
        # Use growpart if available (often safer), fallback to sfdisk
        if command -v growpart > /dev/null && [ -x "$(command -v growpart)" ]; then
           echo "Attempting resize with growpart..."
           ${pkgs.cloud-utils}/bin/growpart "$bootDevice" $partNum || \
             { echo "growpart failed, attempting sfdisk"; echo ",+," | sfdisk -N$partNum --no-reread "$bootDevice"; }
        else
           echo "growpart not found or not executable, using sfdisk..."
           echo ",+," | sfdisk -N$partNum --no-reread "$bootDevice"
        fi

        echo "Running partprobe..."
        ${pkgs.parted}/bin/partprobe "$bootDevice"
        # Wait a moment for the kernel to recognize the change
        sleep 3
        echo "Resizing filesystem..."
        ${pkgs.e2fsprogs}/bin/resize2fs "$rootPart"

        echo "Registering Nix paths..."
        # Register the contents of the initial Nix store
        ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration

        echo "Setting up system profile..."
        # nixos-rebuild also requires a "system" profile and an /etc/NIXOS tag.
        touch /etc/NIXOS
        ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system

        echo "Cleaning up first-boot flag..."
        # Prevents this from running on later boots.
        rm -f /nix-path-registration
        # Sync filesystem changes
        sync
        echo "First boot setup complete. System may reboot if required by resize."
        # Consider adding a reboot command here if resizing often requires it
        # reboot
        set +x
      fi
    '';

  };

  # Ensure the DTB is correctly specified for the hardware section too
  hardware.deviceTree = {
    enable = true;
    name = dtbPath; # Use the variable defined earlier
  };
  hardware.firmware = with pkgs; [
    firmwareLinuxNonfree
    # Add specific firmware if known to be needed, e.g., for WiFi/BT
  ];


  # Basic system packages
  environment.systemPackages = with pkgs; [
    coreutils # Provides dd
    util-linux
    iproute2
    parted # Useful for debugging partition issues
    cloud-utils # Provides growpart
    e2fsprogs # Provides resize2fs
    # Add network tools if needed (e.g., iw for wifi)
  ];

  # Disable graphical elements if not needed
  services.xserver.enable = false;
  documentation.enable = false;
  hardware.pulseaudio.enable = false;

  # Enable SSH for access
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes"; # For initial debugging only - change later!
  };

  # Ensure Nix settings are appropriate
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # System configuration
  system.stateVersion = "23.11"; # Or your desired version

}
