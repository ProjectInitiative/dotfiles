# rockchip-sd-image.nix (Refactored for monolithic image assembly)
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
  # Assuming uboot-build.nix is in the same directory or accessible
  ubootBuilds = import ./uboot-build.nix { inherit pkgs; };
  ubootIdbloaderFile = "${ubootBuilds.uboot-rk3588}/bin/idbloader.img";
  ubootItbFile = "${ubootBuilds.uboot-rk3588}/bin/u-boot.itb";

  # === Kernel and Device Tree Configuration ===
  # (Keep your existing customKernel, dtbName, dtbPath definitions)
  customKernel = pkgs.linuxPackages_6_14; # Example from your config
  dtbName = "rk3582-radxa-e52c.dtb";      # Example from your config
  dtbPath = "rockchip/${dtbName}";        # Example from your config

in
{
  imports = [
    (modulesPath + "/profiles/base.nix") # Common base settings for NixOS
    # (modulesPath + "/installer/sd-card/sd-image.nix") # REMOVE THIS LINE
    # We are replacing the functionality of the standard sd-image.nix
  ];

  # === Options for this custom image building module (Optional) ===
  # You can define new options here if you want to make parts of this new process configurable.
  # For example:
  # options.rockchipImage.outputFileName = mkOption { ... };

  # === NixOS Configuration relevant to the image content ===
  config = {
    # 1. Configure NixOS for U-Boot and extlinux
    boot.loader.generic-extlinux-compatible.enable = true;
    boot.loader.grub.enable = false; # Not used with U-Boot typically

    # Kernel, DTB, and kernel parameters
    boot.kernelPackages = customKernel;
    hardware.deviceTree = {
      enable = true;
      name = dtbPath; # Tells NixOS which DTB to use
    };
    boot.kernelParams = [
      "console=ttyFIQ0,115200n8" # Adjust to your board's primary serial console
      "console=ttyS2,115200n8"
      "earlycon=uart8250,mmio32,0xfeb50000"
      "rootwait"
      # The root device will be identified by the label set on the rootfs partition
      "root=/dev/disk/by-label/NIXOS_ROOT"
      "rw"
      "ignore_loglevel"
      "debug"
      "earlyprintk"
    ];

    # Define the root filesystem for the running system
    fileSystems."/" = {
      device = "/dev/disk/by-label/NIXOS_ROOT"; # Must match volumeLabel and partition name
      fsType = "ext4";
    };
    # Note: No separate VFAT /boot/firmware partition is strictly needed in fstab if
    # U-Boot loads everything from /boot within the ext4 rootfs.

    # Include necessary modules in initrd
    boot.initrd.availableKernelModules = [
      "usbhid" "usb_storage" "sd_mod" "mmc_block" "dw_mmc_rockchip" "ext4"
      # Add other essential modules from your previous config
    ];


    # 2. Build the NixOS Root Filesystem Partition Image
    # This uses make-ext4-fs.nix to create an image of the root partition.
    system.build.nixosRootfsPartitionImage = pkgs.callPackage "${pkgs.path}/nixos/lib/make-ext4-fs.nix" {
      # name = "nixos-rootfs-partition"; # Optional internal name for the derivation
      storePaths = config.system.build.toplevel;
      # storePaths = config.system.build.storePaths; # Essential: paths to include from the NixOS system build
      # Kernel, initrd, DTB, and extlinux.conf will be placed in /boot of this image
      populateImageCommands = ''
        echo "[INFO] Populating /boot directory in rootfs image..."
        # Create /boot directory if it doesn't exist (populateCmd expects it)
        mkdir -p ./files/boot
        # populateCmd copies kernel, initrd, DTB to ./files/boot
        # and creates ./files/boot/extlinux/extlinux.conf
        # ${config.system.build.toplevel} is the NixOS system closure
        ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
        echo "[INFO] /boot directory populated."
      '';
      volumeLabel = "NIXOS_ROOT"; # Filesystem label for the ext4 partition
      # uuid = "your-custom-uuid-if-needed"; # Optional: Filesystem UUID
      # size = "2G"; # Optional: Max size of this ext4 image. If not set, it fits contents.
                     # The final partition can be resized on first boot.
      compressImage = false; # We need the raw .img for the assembler
    };

    # 3. Assemble the Final Monolithic Disk Image
    # This calls your assemble-monolithic-image.nix script, passing the necessary components.
    system.build.finalMonolithicImage = pkgs.callPackage ./assemble-monolithic-image.nix {
      # pkgs and lib are implicitly passed if the function expects them by those names.
      # To be explicit: inherit pkgs lib;
      inherit ubootIdbloaderFile ubootItbFile;
      nixosRootfsImageFile = config.system.build.nixosRootfsPartitionImage; # The rootfs.img we just defined
    };

    # Point the default system build output to your new monolithic image
    # This makes `nix build .#nixosConfigurations.yourSystemName.config.system.build.image` work.
    system.build.image = config.system.build.finalMonolithicImage;
    # You might also want to set image.filePath for naming conventions if using Flakes output attributes.
    # For example:
    # image.fileName = lib.mkDefault "${config.system.nixos.label}-${config.system.nixos.version}-aarch64-linux-e52c-monolithic.img";
    # image.filePath = "images/${config.image.fileName}";


    # Post-boot commands for resizing the root partition (remains crucial)
    # This script runs on the *target device* after it boots your image.
    boot.postBootCommands = lib.mkBefore ''
      # On the first boot do some maintenance tasks
      if [ -f /nix-path-registration ]; then
        set -euo pipefail
        set -x
        
        rootPart=$(${pkgs.util-linux}/bin/findmnt -n -o SOURCE /)
        bootDevice=''$(lsblk -npo PKNAME "$rootPart")
        # Extract partition number (e.g., from /dev/sda2 -> 2, or /dev/mmcblk0p2 -> 2)
        partNumFull="''$(echo "$rootPart" | sed -E "s|^''${bootDevice}(p?)||")"
        partNum="''$(echo "$partNumFull" | sed 's/p//')"

        echo "Root partition: ''${rootPart}, Boot device: ''${bootDevice}, Partition number: ''${partNum}"

        if command -v growpart > /dev/null && [ -x "$(command -v growpart)" ]; then
          echo "Attempting resize with growpart..."
          ${pkgs.cloud-utils}/bin/growpart "''${bootDevice}" "''${partNum}" || \
            { echo "[WARNING] growpart failed, attempting sfdisk as fallback..."; echo ",+," | sfdisk -N"''${partNum}" --no-reread "''${bootDevice}"; }
        else
          echo "growpart not found, using sfdisk..."
          echo ",+," | sfdisk -N"''${partNum}" --no-reread "''${bootDevice}"
        fi

        echo "Running partprobe on ''${bootDevice}..."
        ${pkgs.parted}/bin/partprobe "''${bootDevice}" || echo "[WARNING] partprobe on ''${bootDevice} encountered an issue."
        sleep 3 # Give kernel time to recognize changes

        echo "Resizing filesystem on ''${rootPart}..."
        ${pkgs.e2fsprogs}/bin/resize2fs "''${rootPart}"

        echo "Registering Nix paths..."
        ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration
        echo "Setting up system profile..."
        touch /etc/NIXOS
        ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
        echo "Cleaning up first-boot flag..."
        rm -f /nix-path-registration
        sync
        echo "First boot setup complete."
        set +x
      fi
    '';

    # Keep other necessary configurations from your original file:
    # hardware.firmware, environment.systemPackages, services.openssh, nix.settings, system.stateVersion, etc.
    # Example:
    hardware.firmware = with pkgs; [ firmwareLinuxNonfree ];
    environment.systemPackages = with pkgs; [ coreutils util-linux iproute2 parted cloud-utils e2fsprogs ];
    services.openssh = {
      enable = true;
      settings.PermitRootLogin = "yes"; # For debugging, consider changing for production
    };
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    system.stateVersion = "23.11"; # Or your current version
  };
}
