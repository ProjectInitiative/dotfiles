# rockchip-sd-image.nix
{
  config,
  lib,
  pkgs,
  modulesPath,
  # ### ADDED: Optional path to a custom TPL file you generate for U-Boot
  # ### If you generate one, pass its path here from default.nix
  # customTplFileForUboot ? null,
  # # ### ADDED: Optional path to your ddrbin_param.txt for U-Boot TPL generation
  # ddrParamFileForUboot ? null,
  inputs,
  ...
}:

with lib;

let
  # ### MODIFIED: Pass customTplFile and ddrParamFile to uboot-build
  # ubootBuilds = import ./uboot-build.nix {
  #   inherit pkgs;
  #   customTplFile = customTplFileForUboot;
  #   ddrParamFile = ddrParamFileForUboot;
  # };

  # ubootIdbloaderFile = "${ubootBuilds.uboot-rk3588}/bin/idbloader.img";
  # ubootItbFile = "${ubootBuilds.uboot-rk3588}/bin/u-boot.itb";
  ubootIdbloaderFile = "${pkgs.uboot-rk3582-generic}/idbloader.img";
  ubootItbFile = "${pkgs.uboot-rk3582-generic}/u-boot.itb";

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
      # "console=tty1"
      # "console=ttys2,115200n8" # primary debug console for rk358x u-boot & kernel
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
      # On the first boot, do some maintenance tasks.
      # This script runs in a minimal environment, so we provide full paths to all commands.
      if [ -f /nix-path-registration ]; then
        # Set bash options for safety: exit on error, exit on unset variable, pipefail.
        set -euo pipefail
        # Enable command echoing for debugging.
        set -x

        # --- Define full paths to all our tools upfront for clarity ---
        local FINDMNT="${pkgs.util-linux}/bin/findmnt"
        local LSBLK="${pkgs.util-linux}/bin/lsblk"
        local ECHO="${pkgs.coreutils}/bin/echo"
        local SED="${pkgs.gnused}/bin/sed"
        local SFDISK="${pkgs.util-linux}/bin/sfdisk"
        local GROWPART="${pkgs.cloud-utils}/bin/growpart"
        local PARTPROBE="${pkgs.parted}/bin/partprobe"
        local RESIZE2FS="${pkgs.e2fsprogs}/bin/resize2fs"
        local SLEEP="${pkgs.coreutils}/bin/sleep"
        local RM="${pkgs.coreutils}/bin/rm"
        local SYNC="${pkgs.coreutils}/bin/sync"
        local NIX_STORE="${config.nix.package.out}/bin/nix-store"
        local NIX_ENV="${config.nix.package.out}/bin/nix-env"


        # --- Script Logic ---
        local rootPartDev=$($FINDMNT -n -o SOURCE /)
        local bootDevice=$($LSBLK -npo PKNAME "$rootPartDev")
        # Extract partition number robustly.
        local partNum=$($ECHO "$rootPartDev" | $SED -E 's|^.*[^0-9]([0-9]+)$|\1|')

        $ECHO "Root partition device: ''${rootPartDev}, Boot device: ''${bootDevice}, Root Partition number: ''${partNum}"

        # Attempt to resize the root partition.
        $ECHO "Attempting resize with growpart..."
        # Note: The 'command -v' check is tricky in this environment. We'll just try growpart directly.
        # If cloud-utils is in systemPackages (which it is), growpart should be in the PATH set up for this script.
        # But for max safety, we call it by its full path.
        if $GROWPART "''${bootDevice}" "''${partNum}"; then
            $ECHO "growpart succeeded."
        else
            $ECHO "[WARNING] growpart failed, attempting sfdisk as fallback..."
            $ECHO ",+," | $SFDISK -N"''${partNum}" --no-reread "''${bootDevice}"
        fi

        $ECHO "Running partprobe on ''${bootDevice}..."
        $PARTPROBE "''${bootDevice}" || $ECHO "[WARNING] partprobe on ''${bootDevice} encountered an issue."
        $SLEEP 3 # Give kernel time to recognize changes.

        $ECHO "Resizing filesystem on ''${rootPartDev}..."
        $RESIZE2FS "''${rootPartDev}"

        $ECHO "Registering Nix paths..."
        $NIX_STORE --load-db < /nix-path-registration

        $ECHO "Setting up system profile..."
        $NIX_ENV -p /nix/var/nix/profiles/system --set /run/current-system

        $ECHO "Cleaning up first-boot flag..."
        $RM -f /nix-path-registration
        $SYNC

        $ECHO "First boot setup complete."
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
