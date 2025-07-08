# rockchip-sd-image.nix
{
  config,
  lib,
  pkgs,
  modulesPath,
  # ### ADDED: Optional path to a custom TPL file you generate for U-Boot
  # ### If you generate one, pass its path here from default.nix
  customTplFileForUboot ? null,
  # ### ADDED: Optional path to your ddrbin_param.txt for U-Boot TPL generation
  ddrParamFileForUboot ? null,
  ...
}:

with lib;

let
  # ### MODIFIED: Pass customTplFile and ddrParamFile to uboot-build
  ubootBuilds = import ./uboot-build.nix {
    inherit pkgs;
    customTplFile = customTplFileForUboot;
    ddrParamFile = ddrParamFileForUboot;
  };
  ubootIdbloaderFile = "${ubootBuilds.uboot-rk3588}/bin/idbloader.img";
  ubootItbFile = "${ubootBuilds.uboot-rk3588}/bin/u-boot.itb";

  # ### MODIFIED: Consider using a more specific kernel or Radxa's kernel
  # ### For now, let's stick to pkgs.linuxPackages_latest for simplicity
  # ### but this is a common area for board-specific changes.
  customKernel = pkgs.linuxPackages_latest; # Was pkgs.linuxPackages_6_14
  # ### MODIFIED: Make sure this DTB name is correct for your board AND the kernel version.
  dtbName = "rk3582-radxa-e52c.dtb"; # Example, verify this exists for your kernel
  # dtbName = "rk3588s-evb1-v10.dtb"; # Example, verify this exists for your kernel
  dtbPath = "rockchip/${dtbName}";

  bootVolumeLabel = "NIXOS_BOOT";
  rootVolumeLabel = "NIXOS_ROOT";

  emptyBootDir = pkgs.runCommand "empty-boot-dir" {} ''
    mkdir -p $out/boot
  '';

in
{
  imports = [
    (modulesPath + "/profiles/base.nix")
  ];

  config = {
    boot.loader.generic-extlinux-compatible.enable = true;
    boot.loader.grub.enable = false;

    boot.kernelPackages = customKernel;
    hardware.deviceTree = {
      enable = true;
      name = dtbPath;
    };
    boot.kernelParams = [
      "console=tty1"
      "console=ttyS2,115200n8" # Primary debug console for RK358x U-Boot & Kernel
      "earlycon=uart8250,mmio32,0xfeb50000" # Matches ttyS2 on rk358x
      # "console=ttyFIQ0,115200n8" # Often for SPL/TPL, can be noisy or conflict if ttyS2 is main
      "rootwait"
      "root=/dev/disk/by-label/${rootVolumeLabel}"
      "rw"
      "ignore_loglevel"
      # "debug" # Keep for debugging
      # "earlyprintk" # Keep for debugging
    ];

    fileSystems."/" = {
      device = "/dev/disk/by-label/${rootVolumeLabel}";
      fsType = "ext4";
    };
    fileSystems."/boot" = {
      device = "/dev/disk/by-label/${bootVolumeLabel}";
      fsType = "vfat";
    };

    boot.initrd.availableKernelModules = [
      "usbhid" "usb_storage" "sd_mod" "mmc_block" "dw_mmc_rockchip" "ext4" "vfat" "nls_cp437" "nls_iso8859-1"
      # ### ADDED: Common for USB networking if you use it via UMS/RNDIS from U-Boot later
      "usbnet" "cdc_ether" "rndis_host"
      # ### ADDED: NVMe if your E52C has an M.2 slot and you plan to boot from NVMe eventually
      # "nvme" "nvme_core" "xhci_pci" # xhci_pci might be needed if NVMe is via PCIe
    ];

    system.build.nixosBootPartitionImage = pkgs.callPackage ./make-fat-fs.nix {
      storePaths = [];
      populateImageCommands = ''
        echo "[INFO] Populating /boot VFAT image..."
        mkdir -p ./files
        ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files
        echo "[INFO] /boot VFAT image populated."
      '';
      volumeLabel = bootVolumeLabel;
      size = "256M";
      compressImage = false;
    };

    system.build.nixosRootfsPartitionImage = pkgs.callPackage "${pkgs.path}/nixos/lib/make-ext4-fs.nix" {
      storePaths = config.system.build.toplevel;
      volumeLabel = rootVolumeLabel;
      compressImage = false;
    };

    system.build.finalDiskImages = pkgs.callPackage ./assemble-monolithic-image.nix {
      inherit ubootIdbloaderFile ubootItbFile;
      nixosBootImageFile = config.system.build.nixosBootPartitionImage;
      nixosRootfsImageFile = config.system.build.nixosRootfsPartitionImage;
      buildFullImage = true;
      buildUbootImage = true;
      buildOsImage = true;
    };

    system.build.image = config.system.build.finalDiskImages;

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

    hardware.firmware = with pkgs; [ firmwareLinuxNonfree ];
    environment.systemPackages = with pkgs; [ coreutils util-linux iproute2 parted cloud-utils e2fsprogs emptyBootDir ];
    services.openssh = {
      enable = true;
      settings.PermitRootLogin = "yes";
    };
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    system.stateVersion = "24.11"; # Or your current version
  };
}
