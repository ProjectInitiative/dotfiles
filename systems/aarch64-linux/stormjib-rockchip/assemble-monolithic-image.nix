# assemble-monolithic-image.nix
{ pkgs, lib,
  ubootIdbloaderFile,
  ubootItbFile,
  nixosBootImageFile, # This is the direct path to the fat32 image file
  nixosRootfsImageFile, # This is the direct path to the ext4 image file
  # -- Image type build options --
  buildFullImage ? true,      # Build: U-Boot + Boot Partition + Rootfs Partition
  buildUbootImage ? false,    # Build: U-Boot only (idbloader + itb)
  buildOsImage ? false        # Build: Boot Partition + Rootfs Partition (for SD Card)
}:

let
  # --- U-Boot specific offsets (remain the same) ---
  idbloaderOffsetBytes = 64 * 512;   # 32 KiB -> Sector 64
  itbOffsetBytes = 16384 * 512;  # 8 MiB -> Sector 16384

  # --- Partition Layout Configuration ---
  # Use MiB alignment for partitions for performance/compatibility
  alignmentUnitBytes = 1 * 1024 * 1024; # 1MiB
  bytesToSectors = bytes: bytes / 512;
  alignUp = (val: unit: ((val + unit - 1) / unit) * unit);

  # --- Full Monolithic Image (eMMC Style) ---
  # Start boot partition after U-Boot ITB, aligned.
  # Ensure sufficient space after ITB before aligning (e.g., add a few MiB buffer)
  fullImgBootPartitionStartMinBytes = itbOffsetBytes + (4 * 1024 * 1024); # Start at least 4MiB after ITB end offset
  fullImgBootPartitionStartBytes = alignUp fullImgBootPartitionStartMinBytes alignmentUnitBytes; # Align this start point up
  fullImgBootPartitionStartSectors = bytesToSectors fullImgBootPartitionStartBytes;
  # Rootfs starts immediately after boot partition

  # --- OS Only Image (SD Card Style) ---
  # Start boot partition early, aligned.
  osImgBootPartitionStartBytes = alignUp (1 * 1024 * 1024) alignmentUnitBytes; # Start at 1 MiB
  osImgBootPartitionStartSectors = bytesToSectors osImgBootPartitionStartBytes;
  # Rootfs starts immediately after boot partition

  # --- GPT Partition Type GUIDs ---
  linuxFsTypeGuid = "0FC63DAF-8483-4772-8E79-3D69D8477DE4";
  efiSysTypeGuid = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"; # EFI System Partition

in pkgs.stdenv.mkDerivation {
  name = "nixos-e52c-disk-images";

  srcs = [
    ubootIdbloaderFile
    ubootItbFile
    nixosBootImageFile
    nixosRootfsImageFile
  ];

  nativeBuildInputs = [
    pkgs.coreutils    # For dd, truncate, stat, echo, cat
    pkgs.util-linux   # For sfdisk, uuidgen
    pkgs.parted       # For parted (verification)
  ];

  env = {
    IDBLOADER_FILE_PATH_ENV = ubootIdbloaderFile;
    ITB_FILE_PATH_ENV = ubootItbFile;
    BOOT_IMAGE_FILE_PATH_ENV = nixosBootImageFile; # Direct file path
    ROOTFS_IMAGE_FILE_PATH_ENV = nixosRootfsImageFile; # Direct file path

    IDBLOADER_OFFSET_SECTORS_ENV = builtins.toString (bytesToSectors idbloaderOffsetBytes);
    ITB_OFFSET_SECTORS_ENV = builtins.toString (bytesToSectors itbOffsetBytes);

    FULL_IMG_BOOT_PART_START_SECTORS_ENV = builtins.toString fullImgBootPartitionStartSectors;
    OS_IMG_BOOT_PART_START_SECTORS_ENV = builtins.toString osImgBootPartitionStartSectors;

    ALIGNMENT_BYTES_ENV = builtins.toString alignmentUnitBytes;
    LINUX_FS_GUID_ENV = linuxFsTypeGuid;
    EFI_SYS_GUID_ENV = efiSysTypeGuid;

    BUILD_FULL_IMAGE_ENV = if buildFullImage then "true" else "false";
    BUILD_UBOOT_IMAGE_ENV = if buildUbootImage then "true" else "false";
    BUILD_OS_IMAGE_ENV = if buildOsImage then "true" else "false";
  };

  outputs = [ "out" ];
  phases = [ "buildPhase" "installPhase" ];

  buildPhase = ''
    set -xe # Exit on error, print commands

    local idbloader_file="$IDBLOADER_FILE_PATH_ENV"
    local itb_file="$ITB_FILE_PATH_ENV"
    local boot_img_file="$BOOT_IMAGE_FILE_PATH_ENV"   # Direct file path
    local rootfs_img_file="$ROOTFS_IMAGE_FILE_PATH_ENV" # Direct file path

    local idbloader_offset_sectors="$IDBLOADER_OFFSET_SECTORS_ENV"
    local itb_offset_sectors="$ITB_OFFSET_SECTORS_ENV"
    local full_img_boot_part_start_sectors="$FULL_IMG_BOOT_PART_START_SECTORS_ENV"
    local os_img_boot_part_start_sectors="$OS_IMG_BOOT_PART_START_SECTORS_ENV"
    local alignment_unit_bytes="$ALIGNMENT_BYTES_ENV"
    local linux_fs_guid="$LINUX_FS_GUID_ENV"
    local efi_sys_guid="$EFI_SYS_GUID_ENV"
    local build_full_img="$BUILD_FULL_IMAGE_ENV"
    local build_uboot_img="$BUILD_UBOOT_IMAGE_ENV"
    local build_os_img="$BUILD_OS_IMAGE_ENV"

    # Calculate sizes (cleaned)
    local idbloader_size_bytes=0
    [[ -f "$idbloader_file" ]] && idbloader_size_bytes=$(${pkgs.coreutils}/bin/stat -c %s "$idbloader_file" | ${pkgs.coreutils}/bin/tr -d '[:space:]')
    local itb_size_bytes=0
    [[ -f "$itb_file" ]] && itb_size_bytes=$(${pkgs.coreutils}/bin/stat -c %s "$itb_file" | ${pkgs.coreutils}/bin/tr -d '[:space:]')
    local boot_img_size_bytes=0
    [[ -f "$boot_img_file" ]] && boot_img_size_bytes=$(${pkgs.coreutils}/bin/stat -c %s "$boot_img_file" | ${pkgs.coreutils}/bin/tr -d '[:space:]')
    local rootfs_img_size_bytes=0
    [[ -f "$rootfs_img_file" ]] && rootfs_img_size_bytes=$(${pkgs.coreutils}/bin/stat -c %s "$rootfs_img_file" | ${pkgs.coreutils}/bin/tr -d '[:space:]')

    # Calculate sectors (only if size > 0)
    local boot_img_min_sectors=0
    [[ -n "$boot_img_size_bytes" && "$boot_img_size_bytes" -gt 0 ]] && boot_img_min_sectors=$(($boot_img_size_bytes / 512))
    local rootfs_img_min_sectors=0
    [[ -n "$rootfs_img_size_bytes" && "$rootfs_img_size_bytes" -gt 0 ]] && rootfs_img_min_sectors=$(($rootfs_img_size_bytes / 512))

    echo "--- Input Files ---"
    echo "IDBloader: $idbloader_file (Size: $idbloader_size_bytes bytes)"
    echo "U-Boot ITB: $itb_file (Size: $itb_size_bytes bytes)"
    echo "Boot Image: $boot_img_file (Size: $boot_img_size_bytes bytes, Min Sectors: $boot_img_min_sectors)"
    echo "RootFS Image: $rootfs_img_file (Size: $rootfs_img_size_bytes bytes, Min Sectors: $rootfs_img_min_sectors)"

    # Basic input validation
    if [[ "$build_uboot_img" == "true" || "$build_full_img" == "true" ]]; then
      if (( idbloader_size_bytes <= 0 )); then echo "Error: IDBloader file size is zero or invalid ($idbloader_size_bytes)."; exit 1; fi
      if (( itb_size_bytes <= 0 )); then echo "Error: U-Boot ITB file size is zero or invalid ($itb_size_bytes)."; exit 1; fi
    fi
    if [[ "$build_os_img" == "true" || "$build_full_img" == "true" ]]; then
      # Debug checks (can be removed once stable)
      echo "DEBUG: Value of boot_img_min_sectors before check is: '$boot_img_min_sectors'"
      if [[ "$boot_img_min_sectors" =~ ^[0-9]+$ ]]; then echo "DEBUG: boot_img_min_sectors appears numeric."; else echo "DEBUG: boot_img_min_sectors DOES NOT appear strictly numeric."; fi
      # Main check
      if (( boot_img_min_sectors <= 0 )); then
          echo "Error: Boot image minimum sectors evaluated as zero or less ('$boot_img_min_sectors'). Size was $boot_img_size_bytes bytes. Check path: $boot_img_file"
          exit 1
      fi
      # Debug checks (can be removed once stable)
      echo "DEBUG: Value of rootfs_img_min_sectors before check is: '$rootfs_img_min_sectors'"
      if [[ "$rootfs_img_min_sectors" =~ ^[0-9]+$ ]]; then echo "DEBUG: rootfs_img_min_sectors appears numeric."; else echo "DEBUG: rootfs_img_min_sectors DOES NOT appear strictly numeric."; fi
      # Main check
       if (( rootfs_img_min_sectors <= 0 )); then
           echo "Error: RootFS image minimum sectors evaluated as zero or less ('$rootfs_img_min_sectors'). Size was $rootfs_img_size_bytes bytes. Check path: $rootfs_img_file"
           exit 1
       fi
    fi

    # --- Build U-Boot Only Image ---
    if [[ "$build_uboot_img" == "true" ]]; then
        # ... (uboot-only image logic - no changes) ...
        echo ""
        echo "--- Assembling U-Boot Only Image: uboot-only.img ---"
        local uboot_img_name="uboot-only.img"
        local uboot_img_min_size_bytes=$(($itb_offset_sectors * 512 + $itb_size_bytes))
        local uboot_img_total_size_bytes=$(( (($uboot_img_min_size_bytes + $alignment_unit_bytes - 1) / $alignment_unit_bytes ) * $alignment_unit_bytes ))
        echo "U-Boot image min size: $uboot_img_min_size_bytes, Aligned size: $uboot_img_total_size_bytes bytes"
        echo "[INFO] 1. Creating empty sparse image file: $uboot_img_name"
        "${pkgs.coreutils}/bin/truncate" -s "$uboot_img_total_size_bytes" "$uboot_img_name"
        echo "[INFO] 2. Writing idbloader.img to sector $idbloader_offset_sectors..."
        "${pkgs.coreutils}/bin/dd" if="$idbloader_file" of="$uboot_img_name" seek="$idbloader_offset_sectors" conv=notrunc,fsync bs=512 status=progress
        echo "[INFO] 3. Writing u-boot.itb to sector $itb_offset_sectors..."
        "${pkgs.coreutils}/bin/dd" if="$itb_file" of="$uboot_img_name" seek="$itb_offset_sectors" conv=notrunc,fsync bs=512 status=progress
        echo "--- U-Boot Only image created: $uboot_img_name ---"
    fi

    # --- Build OS Only Image ---
    if [[ "$build_os_img" == "true" ]]; then
      echo ""
      echo "--- Assembling OS Only Image (SD Card): os-only.img ---"
      local os_img_name="os-only.img"
      local os_img_boot_uuid=$(${pkgs.util-linux}/bin/uuidgen)
      local os_img_root_uuid=$(${pkgs.util-linux}/bin/uuidgen) # Generate UUID for rootfs

      local os_img_rootfs_part_start_sectors=$(($os_img_boot_part_start_sectors + $boot_img_min_sectors))
      local os_img_min_size_bytes=$(($os_img_rootfs_part_start_sectors * 512 + $rootfs_img_size_bytes))
      local os_img_total_size_bytes=$(( (($os_img_min_size_bytes + $alignment_unit_bytes - 1) / $alignment_unit_bytes ) * $alignment_unit_bytes ))
      local os_img_total_sectors=$(($os_img_total_size_bytes / 512))

      echo "OS Image Layout:"
      # ... (layout echos) ...

      echo "[INFO] 1. Creating empty sparse image file: $os_img_name"
      "${pkgs.coreutils}/bin/truncate" -s "$os_img_total_size_bytes" "$os_img_name"

      echo "[INFO] 2. Creating GPT partition table on $os_img_name..."
      # Check that partitions fit before calling sfdisk
      local os_img_rootfs_part_end_sector=$(($os_img_rootfs_part_start_sectors + $rootfs_img_min_sectors - 1))
      # Use >= total_sectors check for safety
      if (( os_img_rootfs_part_end_sector >= os_img_total_sectors )); then
         echo "Error: OS image: Calculated rootfs partition end ($os_img_rootfs_part_end_sector) exceeds or equals total sectors ($os_img_total_sectors)."
         exit 1
      fi

      # --- sfdisk heredoc (last-lba REMOVED) ---
      "${pkgs.util-linux}/bin/sfdisk" "$os_img_name" << EOF
label: gpt
unit: sectors
first-lba: 34

# Partition 1: Boot (VFAT, using EFI System Partition type)
name="NIXOS_BOOT", start=$os_img_boot_part_start_sectors, size=$boot_img_min_sectors, type="$efi_sys_guid", uuid="$os_img_boot_uuid"

# Partition 2: Rootfs (EXT4, using Linux Filesystem type)
name="NIXOS_ROOT", start=$os_img_rootfs_part_start_sectors, size=$rootfs_img_min_sectors, type="$linux_fs_guid", uuid="$os_img_root_uuid"
EOF

      echo "[INFO] OS image partition table created. Verifying..."
      "${pkgs.util-linux}/bin/sfdisk" --verify --no-tell-kernel "$os_img_name" || echo "[WARNING] sfdisk verification (OS image) reported issues."
      "${pkgs.util-linux}/bin/sfdisk" -l "$os_img_name"
      "${pkgs.parted}/bin/parted" -s "$os_img_name" print

      echo "[INFO] 3. Writing NixOS boot image to partition 1 (sector $os_img_boot_part_start_sectors)..."
      "${pkgs.coreutils}/bin/dd" if="$boot_img_file" of="$os_img_name" seek="$os_img_boot_part_start_sectors" conv=notrunc,fsync bs=512 status=progress

      echo "[INFO] 4. Writing NixOS rootfs image to partition 2 (sector $os_img_rootfs_part_start_sectors)..."
      "${pkgs.coreutils}/bin/dd" if="$rootfs_img_file" of="$os_img_name" seek="$os_img_rootfs_part_start_sectors" conv=notrunc,fsync bs=512 status=progress

      echo "--- OS Only image created: $os_img_name ---"
    fi

    # --- Build Full Monolithic Image ---
    if [[ "$build_full_img" == "true" ]]; then
      echo ""
      echo "--- Assembling Full Monolithic Image: nixos-e52c-full.img ---"
      local full_img_name="nixos-e52c-full.img"
      local full_img_boot_uuid=$(${pkgs.util-linux}/bin/uuidgen)
      local full_img_root_uuid=$(${pkgs.util-linux}/bin/uuidgen)

      local full_img_rootfs_part_start_sectors=$(($full_img_boot_part_start_sectors + $boot_img_min_sectors))
      local full_img_min_size_bytes=$(($full_img_rootfs_part_start_sectors * 512 + $rootfs_img_size_bytes))
      local full_img_total_size_bytes=$(( (($full_img_min_size_bytes + $alignment_unit_bytes - 1) / $alignment_unit_bytes ) * $alignment_unit_bytes ))
      local full_img_total_sectors=$(($full_img_total_size_bytes / 512))

      echo "Full Image Layout:"
      # ... (layout echos) ...

      echo "[INFO] 1. Creating empty sparse image file: $full_img_name"
      "${pkgs.coreutils}/bin/truncate" -s "$full_img_total_size_bytes" "$full_img_name"

      echo "[INFO] 2. Writing idbloader.img..."
      "${pkgs.coreutils}/bin/dd" if="$idbloader_file" of="$full_img_name" seek="$idbloader_offset_sectors" conv=notrunc,fsync bs=512 status=progress
      echo "[INFO] 3. Writing u-boot.itb..."
      "${pkgs.coreutils}/bin/dd" if="$itb_file" of="$full_img_name" seek="$itb_offset_sectors" conv=notrunc,fsync bs=512 status=progress

      echo "[INFO] 4. Creating GPT partition table on $full_img_name..."
      # Check that partitions fit before calling sfdisk
      local full_img_rootfs_part_end_sector=$(($full_img_rootfs_part_start_sectors + $rootfs_img_min_sectors - 1))
      # Use >= total_sectors check for safety
      if (( full_img_rootfs_part_end_sector >= full_img_total_sectors )); then
         echo "Error: Full image: Calculated rootfs partition end ($full_img_rootfs_part_end_sector) exceeds or equals total sectors ($full_img_total_sectors)."
         exit 1
      fi

      # --- sfdisk heredoc (last-lba REMOVED) ---
      "${pkgs.util-linux}/bin/sfdisk" "$full_img_name" << EOF
label: gpt
unit: sectors
first-lba: 34

# Partition 1: Boot (VFAT, EFI System Partition type)
name="NIXOS_BOOT", start=$full_img_boot_part_start_sectors, size=$boot_img_min_sectors, type="$efi_sys_guid", uuid="$full_img_boot_uuid"

# Partition 2: Rootfs (EXT4, Linux Filesystem type)
name="NIXOS_ROOT", start=$full_img_rootfs_part_start_sectors, size=$rootfs_img_min_sectors, type="$linux_fs_guid", uuid="$full_img_root_uuid"
EOF

      echo "[INFO] Full image partition table created. Verifying..."
      "${pkgs.util-linux}/bin/sfdisk" --verify --no-tell-kernel "$full_img_name" || echo "[WARNING] sfdisk verification (Full image) reported issues."
      "${pkgs.util-linux}/bin/sfdisk" -l "$full_img_name"
      "${pkgs.parted}/bin/parted" -s "$full_img_name" print

      echo "[INFO] 5. Writing NixOS boot image..."
      "${pkgs.coreutils}/bin/dd" if="$boot_img_file" of="$full_img_name" seek="$full_img_boot_part_start_sectors" conv=notrunc,fsync bs=512 status=progress
      echo "[INFO] 6. Writing NixOS rootfs image..."
      "${pkgs.coreutils}/bin/dd" if="$rootfs_img_file" of="$full_img_name" seek="$full_img_rootfs_part_start_sectors" conv=notrunc,fsync bs=512 status=progress

      echo "--- Full monolithic image created: $full_img_name ---"
    fi

    # ... (final warning/completion message) ...
     if [[ "$build_full_img" == "false" && "$build_uboot_img" == "false" && "$build_os_img" == "false" ]]; then
         echo "[WARNING] No image types selected for building. Nothing to do in buildPhase."
     fi
     echo "--- Build phase completed ---"

  ''; # End of buildPhase

  installPhase = ''
    # ... (installPhase - no changes needed) ...
     mkdir -p $out
     local any_image_built=false
     if [[ "$BUILD_UBOOT_IMAGE_ENV" == "true" ]] && [[ -f uboot-only.img ]]; then
       echo "Installing uboot-only.img..."
       mv uboot-only.img $out/uboot-only.img
       any_image_built=true
     fi
     if [[ "$BUILD_OS_IMAGE_ENV" == "true" ]] && [[ -f os-only.img ]]; then
       echo "Installing os-only.img..."
       mv os-only.img $out/os-only.img
       any_image_built=true
     fi
     if [[ "$BUILD_FULL_IMAGE_ENV" == "true" ]] && [[ -f nixos-e52c-full.img ]]; then
       echo "Installing nixos-e52c-full.img..."
       mv nixos-e52c-full.img $out/nixos-e52c-full.img
       any_image_built=true
     fi

     if [[ "$any_image_built" == "false" ]]; then
        echo "[INFO] No images were built or found to install."
        touch $out/.no_images_built_placeholder
     fi
     echo "--- Installation phase completed ---"

  ''; # End of installPhase

  dontStrip = true;
  dontFixup = true;
}
