{ pkgs, lib,
  # U-Boot components
  ubootIdbloaderFile,
  ubootItbFile,

  # Pre-built filesystem images
  nixosBootImageFile,
  nixosRootfsImageFile,

  # Build variant flags
  buildFullImage ? true,
  buildOsImage ? false,
  buildUbootImage ? false,

  # Image layout config
  imageName ? "nixos-rockchip-image",
  imagePaddingMB ? 100,
  fullImageBootOffsetMB ? 16,
  osImageBootOffsetMB ? 1,

  # U-Boot raw offsets (in 512-byte sectors)
  idbloaderOffsetSectors ? 64,
  itbOffsetSectors ? 16384
}:

let
  alignmentUnitBytes = 1 * 1024 * 1024; # 1MiB
  bytesToSectors = bytes: builtins.floor (bytes / 512);

  fullImgBootPartitionStartBytes = fullImageBootOffsetMB * 1024 * 1024;
  fullImgBootPartitionStartSectors = bytesToSectors fullImgBootPartitionStartBytes;

  osImgBootPartitionStartBytes = osImageBootOffsetMB * 1024 * 1024;
  osImgBootPartitionStartSectors = bytesToSectors osImgBootPartitionStartBytes;

  linuxFsTypeGuid = "0FC63DAF-8483-4772-8E79-3D69D8477DE4";
  efiSysTypeGuid = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B";

in pkgs.stdenv.mkDerivation {
  pname = imageName;
  version = "assembled";

  src = null;
  dontUnpack = true;

  inherit ubootIdbloaderFile ubootItbFile nixosBootImageFile nixosRootfsImageFile;
  inherit imagePaddingMB;
  inherit idbloaderOffsetSectors itbOffsetSectors;

  nativeBuildInputs = [
    pkgs.coreutils
    pkgs.util-linux
  ];

  env = {
    BUILD_FULL_IMAGE = if buildFullImage then "true" else "false";
    BUILD_OS_IMAGE = if buildOsImage then "true" else "false";
    BUILD_UBOOT_IMAGE = if buildUbootImage then "true" else "false";
  };

  # --- FIX: Renamed `buildCommand` to `buildPhase` ---
  # This ensures stdenv runs this script and then proceeds to the `installPhase`.
  buildPhase = ''
    set -xe

    local full_img_boot_part_start_sectors=${toString fullImgBootPartitionStartSectors}
    local os_img_boot_part_start_sectors=${toString osImgBootPartitionStartSectors}
    local linux_fs_type_guid="${linuxFsTypeGuid}"
    local efi_sys_type_guid="${efiSysTypeGuid}"
    local alignment_unit_bytes=${toString alignmentUnitBytes}
    local img_name_base="${imageName}"

    # --- Function to assemble the OS-only (SD card) image ---
    build_os_image() {
      echo "--- Assembling OS Only Image (SD Card): ''${img_name_base}-os-only.img ---"
      local os_img_name="''${img_name_base}-os-only.img"
      local boot_img_size_bytes=$(stat -c %s "$nixosBootImageFile")
      local rootfs_img_size_bytes=$(stat -c %s "$nixosRootfsImageFile")
      local boot_img_min_sectors=$(( (boot_img_size_bytes + 511) / 512 ))
      local rootfs_img_min_sectors=$(( (rootfs_img_size_bytes + 511) / 512 ))

      local os_img_rootfs_part_start_sectors=$(( os_img_boot_part_start_sectors + boot_img_min_sectors ))
      local os_img_min_end_bytes=$(( os_img_rootfs_part_start_sectors * 512 + rootfs_img_size_bytes ))

      local val_to_align=$(( os_img_min_end_bytes + (imagePaddingMB * 1024 * 1024) ))
      local os_img_total_size_bytes=$(( (val_to_align + alignment_unit_bytes - 1) / alignment_unit_bytes * alignment_unit_bytes ))

      truncate -s "''${os_img_total_size_bytes}" "''${os_img_name}"

      sfdisk "''${os_img_name}" << EOF
label: gpt
unit: sectors
first-lba: 34
name="NIXOS_BOOT", start=$os_img_boot_part_start_sectors, size=$boot_img_min_sectors, type="$efi_sys_type_guid"
name="NIXOS_ROOT", start=$os_img_rootfs_part_start_sectors, type="$linux_fs_type_guid"
EOF
      dd if="$nixosBootImageFile" of="''${os_img_name}" seek="$os_img_boot_part_start_sectors" conv=notrunc,fsync bs=512 status=progress
      dd if="$nixosRootfsImageFile" of="''${os_img_name}" seek="$os_img_rootfs_part_start_sectors" conv=notrunc,fsync bs=512 status=progress
      echo "--- OS Only image created: ''${os_img_name} ---"
    }

    # --- Function to assemble the full monolithic (eMMC) image ---
    build_full_image() {
      echo "--- Assembling Full Monolithic Image: ''${img_name_base}-full.img ---"
      local full_img_name="''${img_name_base}-full.img"
      local boot_img_size_bytes=$(stat -c %s "$nixosBootImageFile")
      local rootfs_img_size_bytes=$(stat -c %s "$nixosRootfsImageFile")
      local boot_img_min_sectors=$(( (boot_img_size_bytes + 511) / 512 ))
      local rootfs_img_min_sectors=$(( (rootfs_img_size_bytes + 511) / 512 ))

      local full_img_rootfs_part_start_sectors=$(( full_img_boot_part_start_sectors + boot_img_min_sectors ))
      local full_img_min_end_bytes=$(( full_img_rootfs_part_start_sectors * 512 + rootfs_img_size_bytes ))

      local val_to_align=$(( full_img_min_end_bytes + (imagePaddingMB * 1024 * 1024) ))
      local full_img_total_size_bytes=$(( (val_to_align + alignment_unit_bytes - 1) / alignment_unit_bytes * alignment_unit_bytes ))

      truncate -s "''${full_img_total_size_bytes}" "''${full_img_name}"
      dd if="$ubootIdbloaderFile" of="''${full_img_name}" seek="$idbloaderOffsetSectors" conv=notrunc,fsync bs=512 status=progress
      dd if="$ubootItbFile" of="''${full_img_name}" seek="$itbOffsetSectors" conv=notrunc,fsync bs=512 status=progress

      sfdisk "''${full_img_name}" << EOF
label: gpt
unit: sectors
first-lba: 34
name="NIXOS_BOOT", start=$full_img_boot_part_start_sectors, size=$boot_img_min_sectors, type="$efi_sys_type_guid"
name="NIXOS_ROOT", start=$full_img_rootfs_part_start_sectors, type="$linux_fs_type_guid"
EOF
      dd if="$nixosBootImageFile" of="''${full_img_name}" seek="$full_img_boot_part_start_sectors" conv=notrunc,fsync bs=512 status=progress
      dd if="$nixosRootfsImageFile" of="''${full_img_name}" seek="$full_img_rootfs_part_start_sectors" conv=notrunc,fsync bs=512 status=progress
      echo "--- Full monolithic image created: ''${full_img_name} ---"
    }

    # --- Function to assemble U-Boot only image ---
    build_uboot_image() {
        echo "--- Assembling U-Boot Only Image: ''${img_name_base}-uboot-only.img ---"
        local uboot_img_name="''${img_name_base}-uboot-only.img"
        local itb_size_bytes=$(stat -c %s "$ubootItbFile")
        
        local uboot_img_min_end_bytes=$((itbOffsetSectors * 512 + itb_size_bytes))
        local uboot_img_total_size_bytes=$(( (uboot_img_min_end_bytes + alignment_unit_bytes - 1) / alignment_unit_bytes * alignment_unit_bytes ))
        if (( uboot_img_total_size_bytes < 16 * 1024 * 1024 )); then uboot_img_total_size_bytes=$((16 * 1024 * 1024)); fi

        truncate -s "''${uboot_img_total_size_bytes}" "''${uboot_img_name}"
        dd if="$ubootIdbloaderFile" of="''${uboot_img_name}" seek="$idbloaderOffsetSectors" conv=notrunc,fsync bs=512 status=progress
        dd if="$ubootItbFile" of="''${uboot_img_name}" seek="$itbOffsetSectors" conv=notrunc,fsync bs=512 status=progress
        echo "--- U-Boot Only image created: ''${uboot_img_name} ---"
    }

    # --- Main Execution ---
    if [ "$BUILD_FULL_IMAGE" = "true" ]; then
      build_full_image
    fi
    if [ "$BUILD_OS_IMAGE" = "true" ]; then
      build_os_image
    fi
    if [ "$BUILD_UBOOT_IMAGE" = "true" ]; then
      build_uboot_image
    fi
  '';

  # This phase will now be executed correctly after the buildPhase completes.
  installPhase = ''
    mkdir -p $out
    if [[ -f "${imageName}-os-only.img" ]]; then
      mv "${imageName}-os-only.img" $out/
    fi
    if [[ -f "${imageName}-full.img" ]]; then
      mv "${imageName}-full.img" $out/
    fi
    if [[ -f "${imageName}-uboot-only.img" ]]; then
      mv "${imageName}-uboot-only.img" $out/
    fi
  '';

  dontStrip = true;
  dontFixup = true;
}
