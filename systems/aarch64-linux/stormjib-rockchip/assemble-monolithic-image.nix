# assemble-monolithic-image.nix
{ pkgs, lib,
  ubootIdbloaderFile,
  ubootItbFile,
  nixosBootImageFile,
  nixosRootfsImageFile,
  buildFullImage ? true,
  buildUbootImage ? false,
  buildOsImage ? false
}:

let
  idbloaderOffsetBytes = 64 * 512;   # 32 KiB -> Sector 64
  itbOffsetBytes = 16384 * 512;  # 8 MiB -> Sector 16384

  alignmentUnitBytes = 1 * 1024 * 1024; # 1MiB
  bytesToSectors = bytes: bytes / 512;
  alignUp = (val: unit: ((val + unit - 1) / unit) * unit);

  # --- Full Monolithic Image (eMMC Style) ---
  # ### MODIFIED: Start boot partition at 16MiB to align with Radxa's parameter_gpt.txt
  fullImgBootPartitionStartMinBytes = 16 * 1024 * 1024; # Start boot partition at 16MiB
  fullImgBootPartitionStartBytes = alignUp fullImgBootPartitionStartMinBytes alignmentUnitBytes;
  fullImgBootPartitionStartSectors = bytesToSectors fullImgBootPartitionStartBytes;

  # --- OS Only Image (SD Card Style) ---
  osImgBootPartitionStartBytes = alignUp (1 * 1024 * 1024) alignmentUnitBytes; # Start at 1 MiB
  osImgBootPartitionStartSectors = bytesToSectors osImgBootPartitionStartBytes;

  linuxFsTypeGuid = "0FC63DAF-8483-4772-8E79-3D69D8477DE4";
  efiSysTypeGuid = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B";

in pkgs.stdenv.mkDerivation {
  name = "nixos-e52c-disk-images";

  srcs = [
    ubootIdbloaderFile
    ubootItbFile
    nixosBootImageFile
    nixosRootfsImageFile
  ];

  nativeBuildInputs = [
    pkgs.coreutils
    pkgs.util-linux
    pkgs.parted
  ];

  env = {
    IDBLOADER_FILE_PATH_ENV = ubootIdbloaderFile;
    ITB_FILE_PATH_ENV = ubootItbFile;
    BOOT_IMAGE_FILE_PATH_ENV = nixosBootImageFile;
    ROOTFS_IMAGE_FILE_PATH_ENV = nixosRootfsImageFile;

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
    set -xe

    local idbloader_file="$IDBLOADER_FILE_PATH_ENV"
    local itb_file="$ITB_FILE_PATH_ENV"
    local boot_img_file="$BOOT_IMAGE_FILE_PATH_ENV"
    local rootfs_img_file="$ROOTFS_IMAGE_FILE_PATH_ENV"

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

    local idbloader_size_bytes=0
    [[ -f "$idbloader_file" ]] && idbloader_size_bytes=$(${pkgs.coreutils}/bin/stat -c %s "$idbloader_file" | ${pkgs.coreutils}/bin/tr -d '[:space:]')
    local itb_size_bytes=0
    [[ -f "$itb_file" ]] && itb_size_bytes=$(${pkgs.coreutils}/bin/stat -c %s "$itb_file" | ${pkgs.coreutils}/bin/tr -d '[:space:]')
    local boot_img_size_bytes=0
    [[ -f "$boot_img_file" ]] && boot_img_size_bytes=$(${pkgs.coreutils}/bin/stat -c %s "$boot_img_file" | ${pkgs.coreutils}/bin/tr -d '[:space:]')
    local rootfs_img_size_bytes=0
    [[ -f "$rootfs_img_file" ]] && rootfs_img_size_bytes=$(${pkgs.coreutils}/bin/stat -c %s "$rootfs_img_file" | ${pkgs.coreutils}/bin/tr -d '[:space:]')

    local boot_img_min_sectors=0
    [[ -n "$boot_img_size_bytes" && "$boot_img_size_bytes" -gt 0 ]] && boot_img_min_sectors=$(( ($boot_img_size_bytes + 511) / 512 )) # Ensure sectors cover full size
    local rootfs_img_min_sectors=0
    [[ -n "$rootfs_img_size_bytes" && "$rootfs_img_size_bytes" -gt 0 ]] && rootfs_img_min_sectors=$(( ($rootfs_img_size_bytes + 511) / 512 )) # Ensure sectors cover full size

    echo "--- Input Files ---"
    echo "IDBloader: $idbloader_file (Size: $idbloader_size_bytes bytes)"
    echo "U-Boot ITB: $itb_file (Size: $itb_size_bytes bytes)"
    echo "Boot Image: $boot_img_file (Size: $boot_img_size_bytes bytes, Min Sectors: $boot_img_min_sectors)"
    echo "RootFS Image: $rootfs_img_file (Size: $rootfs_img_size_bytes bytes, Min Sectors: $rootfs_img_min_sectors)"

    if [[ "$build_uboot_img" == "true" || "$build_full_img" == "true" ]]; then
      if (( idbloader_size_bytes <= 0 )); then echo "Error: IDBloader file size is zero or invalid ($idbloader_size_bytes)."; exit 1; fi
      if (( itb_size_bytes <= 0 )); then echo "Error: U-Boot ITB file size is zero or invalid ($itb_size_bytes)."; exit 1; fi
    fi
    if [[ "$build_os_img" == "true" || "$build_full_img" == "true" ]]; then
      if (( boot_img_min_sectors <= 0 )); then
          echo "Error: Boot image minimum sectors evaluated as zero or less ('$boot_img_min_sectors'). Size was $boot_img_size_bytes bytes. Check path: $boot_img_file"
          exit 1
      fi
       if (( rootfs_img_min_sectors <= 0 )); then
           echo "Error: RootFS image minimum sectors evaluated as zero or less ('$rootfs_img_min_sectors'). Size was $rootfs_img_size_bytes bytes. Check path: $rootfs_img_file"
           exit 1
       fi
    fi

    # --- Build U-Boot Only Image ---
    if [[ "$build_uboot_img" == "true" ]]; then
        echo ""
        echo "--- Assembling U-Boot Only Image: uboot-only.img ---"
        local uboot_img_name="uboot-only.img"
        # ### MODIFIED: Ensure image is large enough for ITB at its offset + ITB size
        local uboot_img_min_end_bytes=$(($itb_offset_sectors * 512 + $itb_size_bytes))
        local uboot_img_total_size_bytes=$(( (($uboot_img_min_end_bytes + $alignment_unit_bytes - 1) / $alignment_unit_bytes ) * $alignment_unit_bytes ))
        # Ensure minimum 16MB for uboot only image if it's smaller, to be safe with some tools/expectations
        if (( uboot_img_total_size_bytes < 16 * 1024 * 1024 )); then uboot_img_total_size_bytes=$((16 * 1024 * 1024)); fi

        echo "U-Boot image min end: $uboot_img_min_end_bytes, Aligned total size: $uboot_img_total_size_bytes bytes"
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
      local os_img_root_uuid=$(${pkgs.util-linux}/bin/uuidgen)

      local os_img_rootfs_part_start_sectors=$(($os_img_boot_part_start_sectors + $boot_img_min_sectors))
      local os_img_min_end_bytes=$(($os_img_rootfs_part_start_sectors * 512 + $rootfs_img_size_bytes))
      # ### MODIFIED: Add some padding to the OS image size (e.g., 100MB) to avoid issues with exact fits
      local os_img_total_size_bytes=$(( (($os_img_min_end_bytes + 100 * 1024 * 1024 + $alignment_unit_bytes - 1) / $alignment_unit_bytes ) * $alignment_unit_bytes ))
      local os_img_total_sectors=$(($os_img_total_size_bytes / 512))

      echo "OS Image Layout:"
      echo "  Boot Partition Start: Sector $os_img_boot_part_start_sectors (Size: $boot_img_min_sectors sectors)"
      echo "  RootFS Partition Start: Sector $os_img_rootfs_part_start_sectors (Size: $rootfs_img_min_sectors sectors)"
      echo "  OS Image Total Size: $os_img_total_size_bytes bytes ($os_img_total_sectors sectors)"


      echo "[INFO] 1. Creating empty sparse image file: $os_img_name"
      "${pkgs.coreutils}/bin/truncate" -s "$os_img_total_size_bytes" "$os_img_name"

      echo "[INFO] 2. Creating GPT partition table on $os_img_name..."
      local os_img_rootfs_part_end_sector=$(($os_img_rootfs_part_start_sectors + $rootfs_img_min_sectors - 1))
      if (( os_img_rootfs_part_end_sector >= os_img_total_sectors )); then
         echo "Error: OS image: Calculated rootfs partition end ($os_img_rootfs_part_end_sector) exceeds or equals total sectors ($os_img_total_sectors)."
         exit 1
      fi

      "${pkgs.util-linux}/bin/sfdisk" "$os_img_name" << EOF
label: gpt
unit: sectors
first-lba: 34

name="NIXOS_BOOT", start=$os_img_boot_part_start_sectors, size=$boot_img_min_sectors, type="$efi_sys_guid", uuid="$os_img_boot_uuid"
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

    if [[ "$build_full_img" == "true" ]]; then
      echo ""
      echo "--- Assembling Full Monolithic Image: nixos-e52c-full.img ---"
      local full_img_name="nixos-e52c-full.img"
      local full_img_boot_uuid=$(${pkgs.util-linux}/bin/uuidgen)
      local full_img_root_uuid=$(${pkgs.util-linux}/bin/uuidgen)

      local full_img_rootfs_part_start_sectors=$(($full_img_boot_part_start_sectors + $boot_img_min_sectors))
      local full_img_min_end_bytes=$(($full_img_rootfs_part_start_sectors * 512 + $rootfs_img_size_bytes))
      # ### MODIFIED: Add some padding to the full image size (e.g., 100MB)
      local full_img_total_size_bytes=$(( (($full_img_min_end_bytes + 100 * 1024 * 1024 + $alignment_unit_bytes - 1) / $alignment_unit_bytes ) * $alignment_unit_bytes ))
      local full_img_total_sectors=$(($full_img_total_size_bytes / 512))

      echo "Full Image Layout:"
      echo "  IDBLoader Offset: Sector $idbloader_offset_sectors"
      echo "  U-Boot ITB Offset: Sector $itb_offset_sectors"
      echo "  Boot Partition Start: Sector $full_img_boot_part_start_sectors (Size: $boot_img_min_sectors sectors)"
      echo "  RootFS Partition Start: Sector $full_img_rootfs_part_start_sectors (Size: $rootfs_img_min_sectors sectors)"
      echo "  Full Image Total Size: $full_img_total_size_bytes bytes ($full_img_total_sectors sectors)"


      echo "[INFO] 1. Creating empty sparse image file: $full_img_name"
      "${pkgs.coreutils}/bin/truncate" -s "$full_img_total_size_bytes" "$full_img_name"

      echo "[INFO] 2. Writing idbloader.img..."
      "${pkgs.coreutils}/bin/dd" if="$idbloader_file" of="$full_img_name" seek="$idbloader_offset_sectors" conv=notrunc,fsync bs=512 status=progress
      echo "[INFO] 3. Writing u-boot.itb..."
      "${pkgs.coreutils}/bin/dd" if="$itb_file" of="$full_img_name" seek="$itb_offset_sectors" conv=notrunc,fsync bs=512 status=progress

      echo "[INFO] 4. Creating GPT partition table on $full_img_name..."
      local full_img_rootfs_part_end_sector=$(($full_img_rootfs_part_start_sectors + $rootfs_img_min_sectors - 1))
      if (( full_img_rootfs_part_end_sector >= full_img_total_sectors )); then
         echo "Error: Full image: Calculated rootfs partition end ($full_img_rootfs_part_end_sector) exceeds or equals total sectors ($full_img_total_sectors)."
         exit 1
      fi

      "${pkgs.util-linux}/bin/sfdisk" "$full_img_name" << EOF
label: gpt
unit: sectors
first-lba: 34

name="NIXOS_BOOT", start=$full_img_boot_part_start_sectors, size=$boot_img_min_sectors, type="$efi_sys_guid", uuid="$full_img_boot_uuid"
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

     if [[ "$build_full_img" == "false" && "$build_uboot_img" == "false" && "$build_os_img" == "false" ]]; then
         echo "[WARNING] No image types selected for building. Nothing to do in buildPhase."
     fi
     echo "--- Build phase completed ---"
  '';

  installPhase = ''
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
       mv nixos-e52c-full.img $out/nixos-e52c-full.img # This will be the primary output for flakes
       any_image_built=true
     fi

     if [[ "$any_image_built" == "false" ]]; then
        echo "[INFO] No images were built or found to install."
        touch $out/.no_images_built_placeholder # Create a placeholder if no images built
     else
        # ### ADDED: Ensure there's at least one primary output file if any image was built
        # If building full image, that's the primary. Otherwise, pick one.
        if [[ "$BUILD_FULL_IMAGE_ENV" == "true" ]] && [[ -f $out/nixos-e52c-full.img ]]; then
            echo "Default output will be nixos-e52c-full.img"
        elif [[ "$BUILD_OS_IMAGE_ENV" == "true" ]] && [[ -f $out/os-only.img ]]; then
            ln -s $out/os-only.img $out/default.img
        elif [[ "$BUILD_UBOOT_IMAGE_ENV" == "true" ]] && [[ -f $out/uboot-only.img ]]; then
            ln -s $out/uboot-only.img $out/default.img
        fi
     fi
     echo "--- Installation phase completed ---"
  '';

  dontStrip = true;
  dontFixup = true;
}
