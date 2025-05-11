# assemble-monolithic-image.nix
{ pkgs, lib, ubootIdbloaderFile, ubootItbFile, nixosRootfsImageFile,
  # -- Image type build options --
  buildFullImage ? true,      # Build the full monolithic image (eMMC)
  buildUbootImage ? false,    # Build U-Boot only image (for eMMC programming)
  buildOsImage ? false        # Build OS only image (for SD card)
}:

let
  # --- Configuration for Full Monolithic Image ---
  fullImgRootfsPartitionStartMiB = 32; # Start NixOS rootfs partition at 32MiB for the full image
  fullImgRootfsPartitionStartBytes = fullImgRootfsPartitionStartMiB * 1024 * 1024;
  fullImgRootfsPartitionStartSectors = fullImgRootfsPartitionStartBytes / 512;

  # --- Configuration for OS Only Image (SD Card) ---
  osImgRootfsPartitionStartMiB = 1; # Start NixOS rootfs partition at 1MiB for the OS-only image
  osImgRootfsPartitionStartBytes = osImgRootfsPartitionStartMiB * 1024 * 1024;
  osImgRootfsPartitionStartSectors = osImgRootfsPartitionStartBytes / 512;

  # --- U-Boot specific offsets (used in multiple image types) ---
  idbloaderOffsetBytes = 64 * 512;   # 32 KiB
  itbOffsetBytes = 16384 * 512; # 8 MiB

in pkgs.stdenv.mkDerivation {
  name = "nixos-e52c-disk-images";

  srcs = [
    ubootIdbloaderFile
    ubootItbFile
    nixosRootfsImageFile
  ];

  nativeBuildInputs = [
    pkgs.coreutils  # For dd, truncate, stat, echo, cat
    pkgs.util-linux # For sfdisk, uuidgen
    pkgs.parted     # For parted (verification)
  ];

  env = {
    IDBLOADER_FILE_PATH_ENV = ubootIdbloaderFile;
    ITB_FILE_PATH_ENV = ubootItbFile;
    ROOTFS_IMAGE_FILE_PATH_ENV = nixosRootfsImageFile;

    FULL_IMG_ROOTFS_START_SECTORS_ENV = builtins.toString fullImgRootfsPartitionStartSectors;
    FULL_IMG_ROOTFS_START_MIB_ENV = builtins.toString fullImgRootfsPartitionStartMiB;

    OS_IMG_ROOTFS_START_SECTORS_ENV = builtins.toString osImgRootfsPartitionStartSectors;
    OS_IMG_ROOTFS_START_MIB_ENV = builtins.toString osImgRootfsPartitionStartMiB;

    IDBLOADER_OFFSET_SECTORS_ENV = builtins.toString (idbloaderOffsetBytes / 512);
    ITB_OFFSET_SECTORS_ENV = builtins.toString (itbOffsetBytes / 512);

    BUILD_FULL_IMAGE_ENV = if buildFullImage then "true" else "false";
    BUILD_UBOOT_IMAGE_ENV = if buildUbootImage then "true" else "false";
    BUILD_OS_IMAGE_ENV = if buildOsImage then "true" else "false";
  };

  phases = [ "buildPhase" "installPhase" ];

  buildPhase = ''
    set -xe

    local idbloader_file="$IDBLOADER_FILE_PATH_ENV"
    local itb_file="$ITB_FILE_PATH_ENV"
    local rootfs_img_file="$ROOTFS_IMAGE_FILE_PATH_ENV"

    local full_img_rootfs_start_sectors="$FULL_IMG_ROOTFS_START_SECTORS_ENV"
    local full_img_rootfs_start_mib="$FULL_IMG_ROOTFS_START_MIB_ENV"

    local os_img_rootfs_start_sectors="$OS_IMG_ROOTFS_START_SECTORS_ENV"
    local os_img_rootfs_start_mib="$OS_IMG_ROOTFS_START_MIB_ENV"

    local idbloader_offset_sectors="$IDBLOADER_OFFSET_SECTORS_ENV"
    local itb_offset_sectors="$ITB_OFFSET_SECTORS_ENV"

    local build_full_img="$BUILD_FULL_IMAGE_ENV"
    local build_uboot_img="$BUILD_UBOOT_IMAGE_ENV"
    local build_os_img="$BUILD_OS_IMAGE_ENV"

    echo "--- Input Files (resolved paths in sandbox) ---"
    local idbloader_size_bytes=$(${pkgs.coreutils}/bin/stat -c %s "$idbloader_file")
    local itb_size_bytes=$(${pkgs.coreutils}/bin/stat -c %s "$itb_file")
    local rootfs_img_size_bytes=$(${pkgs.coreutils}/bin/stat -c %s "$rootfs_img_file")

    echo "IDBloader: $idbloader_file (Size: '$idbloader_size_bytes' bytes)"
    echo "U-Boot ITB: $itb_file (Size: '$itb_size_bytes' bytes)"
    echo "NixOS RootFS: $rootfs_img_file (Size: '$rootfs_img_size_bytes' bytes)"

    local rootfs_img_sectors=$(($rootfs_img_size_bytes / 512))
    if (( $rootfs_img_sectors <= 0 && ( "$build_full_img" == "true" || "$build_os_img" == "true" ) )); then
      echo "Error: RootFS image size is zero or invalid ($rootfs_img_sectors sectors), but a rootfs-dependent image is requested."
      exit 1
    fi

    local alignment_unit_bytes=$((1 * 1024 * 1024)) # 1MiB

    # --- Build U-Boot Only Image (if requested) ---
    if [[ "$build_uboot_img" == "true" ]]; then
      echo ""
      echo "--- Assembling U-Boot Only Image: uboot-only.img ---"
      local uboot_img_name="uboot-only.img"
      local uboot_img_min_size_bytes=$(($itb_offset_sectors * 512 + $itb_size_bytes))
      local uboot_img_total_size_bytes=$(( (($uboot_img_min_size_bytes + $alignment_unit_bytes - 1) / $alignment_unit_bytes ) * $alignment_unit_bytes ))
      echo "U-Boot image size: $uboot_img_total_size_bytes bytes"
      echo "[INFO] 1. Creating empty sparse image file: $uboot_img_name"
      "${pkgs.coreutils}/bin/truncate" -s "$uboot_img_total_size_bytes" "$uboot_img_name"
      echo "[INFO] 2. Writing idbloader.img (SPL) to sector $idbloader_offset_sectors..."
      "${pkgs.coreutils}/bin/dd" if="$idbloader_file" of="$uboot_img_name" seek="$idbloader_offset_sectors" conv=notrunc,fsync bs=512 status=progress
      echo "[INFO] 3. Writing u-boot.itb (Main U-Boot) to sector $itb_offset_sectors..."
      "${pkgs.coreutils}/bin/dd" if="$itb_file" of="$uboot_img_name" seek="$itb_offset_sectors" conv=notrunc,fsync bs=512 status=progress
      echo "--- U-Boot Only image created: $uboot_img_name ---"
    fi

    # --- Build OS Only Image (if requested) ---
    if [[ "$build_os_img" == "true" ]]; then
      echo ""
      echo "--- Assembling OS Only Image (for SD Card): os-only.img ---"
      local os_img_name="os-only.img"
      echo "OS Image Layout Configuration:"
      echo "RootFS Partition will start at sector: $os_img_rootfs_start_sectors (''${os_img_rootfs_start_mib} MiB)"
      echo "RootFS Image Size: $rootfs_img_size_bytes bytes ($rootfs_img_sectors sectors)"
      local os_img_rootfs_start_bytes_sh=$(($os_img_rootfs_start_sectors * 512))
      local os_img_total_size_bytes_unaligned=$(($os_img_rootfs_start_bytes_sh + $rootfs_img_size_bytes))
      local os_img_total_size_bytes=$(( (($os_img_total_size_bytes_unaligned + $alignment_unit_bytes - 1) / $alignment_unit_bytes ) * $alignment_unit_bytes ))
      local os_img_total_sectors=$(($os_img_total_size_bytes / 512))
      echo "OS Image Total Size: $os_img_total_size_bytes bytes ($os_img_total_sectors sectors)"
      echo "[INFO] 1. Creating empty sparse image file: $os_img_name"
      "${pkgs.coreutils}/bin/truncate" -s "$os_img_total_size_bytes" "$os_img_name"
      echo "[INFO] 2. Creating GPT partition table on $os_img_name..."
      local os_img_rootfs_partition_end_sector=$(($os_img_rootfs_start_sectors + $rootfs_img_sectors - 1))
      local os_img_last_lba_for_sfdisk=$(($os_img_total_sectors - 1))
      if (( $os_img_rootfs_partition_end_sector > $os_img_last_lba_for_sfdisk )); then
        echo "Error: OS image: Calculated rootfs partition end sector ($os_img_rootfs_partition_end_sector) exceeds image last LBA ($os_img_last_lba_for_sfdisk)."
        exit 1
      fi

      "${pkgs.util-linux}/bin/sfdisk" "$os_img_name" << EOF
label: gpt
unit: sectors
first-lba: 34

name="NIXOS_SD_ROOT", start=$os_img_rootfs_start_sectors, size=$rootfs_img_sectors, type="0FC63DAF-8483-4772-8E79-3D69D8477DE4", uuid="$(${pkgs.util-linux}/bin/uuidgen)"
EOF

      echo "[INFO] OS image partition table created. Verifying..."
      "${pkgs.util-linux}/bin/sfdisk" --verify --no-tell-kernel "$os_img_name" || echo "[WARNING] sfdisk verification (OS image) reported issues."
      "${pkgs.util-linux}/bin/sfdisk" -l "$os_img_name"
      "${pkgs.parted}/bin/parted" -s "$os_img_name" print
      echo "[INFO] 3. Writing NixOS rootfs image into its partition (starting at sector $os_img_rootfs_start_sectors)..."
      "${pkgs.coreutils}/bin/dd" if="$rootfs_img_file" of="$os_img_name" seek="$os_img_rootfs_start_sectors" conv=notrunc,fsync bs=512 status=progress
      echo "--- OS Only image created: $os_img_name ---"
    fi

    # --- Build Full Monolithic Image (if requested) ---
    if [[ "$build_full_img" == "true" ]]; then
      echo ""
      echo "--- Assembling Full Monolithic Image: nixos-e52c-full.img ---"
      local full_img_name="nixos-e52c-full.img"
      echo "Full Image Layout Configuration:"
      echo "RootFS Partition will start at sector: $full_img_rootfs_start_sectors (''${full_img_rootfs_start_mib} MiB)"
      echo "RootFS Image Size: $rootfs_img_size_bytes bytes ($rootfs_img_sectors sectors)"
      local full_img_rootfs_start_bytes_sh=$(($full_img_rootfs_start_sectors * 512))
      local full_img_total_size_bytes_unaligned=$(($full_img_rootfs_start_bytes_sh + $rootfs_img_size_bytes))
      local full_img_total_size_bytes=$(( (($full_img_total_size_bytes_unaligned + $alignment_unit_bytes - 1) / $alignment_unit_bytes ) * $alignment_unit_bytes ))
      local full_img_total_sectors=$(($full_img_total_size_bytes / 512))
      echo "Full Image Total Size: $full_img_total_size_bytes bytes ($full_img_total_sectors sectors)"
      echo "[INFO] 1. Creating empty sparse image file: $full_img_name"
      "${pkgs.coreutils}/bin/truncate" -s "$full_img_total_size_bytes" "$full_img_name"
      echo "[INFO] 2. Writing idbloader.img (SPL) to sector $idbloader_offset_sectors..."
      "${pkgs.coreutils}/bin/dd" if="$idbloader_file" of="$full_img_name" seek="$idbloader_offset_sectors" conv=notrunc,fsync bs=512 status=progress
      echo "[INFO] 3. Writing u-boot.itb (Main U-Boot) to sector $itb_offset_sectors..."
      "${pkgs.coreutils}/bin/dd" if="$itb_file" of="$full_img_name" seek="$itb_offset_sectors" conv=notrunc,fsync bs=512 status=progress
      echo "[INFO] 4. Creating GPT partition table on $full_img_name..."
      local full_img_rootfs_partition_end_sector=$(($full_img_rootfs_start_sectors + $rootfs_img_sectors - 1))
      local full_img_last_lba_for_sfdisk=$(($full_img_total_sectors - 1))
      if (( $full_img_rootfs_partition_end_sector > $full_img_last_lba_for_sfdisk )); then
        echo "Error: Full image: Calculated rootfs partition end sector ($full_img_rootfs_partition_end_sector) exceeds image last LBA ($full_img_last_lba_for_sfdisk)."
        exit 1
      fi

      "${pkgs.util-linux}/bin/sfdisk" "$full_img_name" << EOF
label: gpt
unit: sectors
first-lba: 34

name="NIXOS_ROOT", start=$full_img_rootfs_start_sectors, size=$rootfs_img_sectors, type="0FC63DAF-8483-4772-8E79-3D69D8477DE4", uuid="$(${pkgs.util-linux}/bin/uuidgen)"
EOF

      echo "[INFO] Full image partition table created. Verifying..."
      "${pkgs.util-linux}/bin/sfdisk" --verify --no-tell-kernel "$full_img_name" || echo "[WARNING] sfdisk verification (Full image) reported issues."
      "${pkgs.util-linux}/bin/sfdisk" -l "$full_img_name"
      "${pkgs.parted}/bin/parted" -s "$full_img_name" print
      echo "[INFO] 5. Writing NixOS rootfs image into its partition (starting at sector $full_img_rootfs_start_sectors)..."
      "${pkgs.coreutils}/bin/dd" if="$rootfs_img_file" of="$full_img_name" seek="$full_img_rootfs_start_sectors" conv=notrunc,fsync bs=512 status=progress
      echo "--- Full monolithic image created: $full_img_name ---"
    fi

    if [[ "$build_full_img" == "false" && "$build_uboot_img" == "false" && "$build_os_img" == "false" ]]; then
        echo "[WARNING] No image types selected for building. Nothing to do in buildPhase."
    fi
    echo "--- Build phase completed ---"
  ''; # End of buildPhase

  installPhase = ''
    mkdir -p $out
    if [[ "$BUILD_UBOOT_IMAGE_ENV" == "true" ]]; then
      echo "Installing uboot-only.img..."
      mv uboot-only.img $out/uboot-only.img
    fi
    if [[ "$BUILD_OS_IMAGE_ENV" == "true" ]]; then
      echo "Installing os-only.img..."
      mv os-only.img $out/os-only.img
    fi
    if [[ "$BUILD_FULL_IMAGE_ENV" == "true" ]]; then
      echo "Installing nixos-e52c-full.img..."
      mv nixos-e52c-full.img $out/nixos-e52c-full.img
    fi
    if [[ "$BUILD_FULL_IMAGE_ENV" == "false" && "$BUILD_UBOOT_IMAGE_ENV" == "false" && "$BUILD_OS_IMAGE_ENV" == "false" ]]; then
        echo "[INFO] No images were built, so nothing to install."
        touch $out/.no_images_built_placeholder
    fi
  '';
}
