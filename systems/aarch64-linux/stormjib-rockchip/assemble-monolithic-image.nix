# assemble-monolithic-image.nix
{ pkgs, lib, ubootIdbloaderFile, ubootItbFile, nixosRootfsImageFile }:

let
  # Configuration for offsets and partition start (Nix variables)
  rootfsPartitionStartMiB = 32; # Start NixOS rootfs partition at 32MiB
  rootfsPartitionStartBytes = rootfsPartitionStartMiB * 1024 * 1024;
  rootfsPartitionStartSectors = rootfsPartitionStartBytes / 512;

in pkgs.stdenv.mkDerivation {
  name = "nixos-e52c-monolithic-disk-image";

  srcs = [
    ubootIdbloaderFile
    ubootItbFile
    nixosRootfsImageFile
  ];

  nativeBuildInputs = [
    pkgs.coreutils    # For dd, truncate, stat
    pkgs.util-linux   # For sfdisk, uuidgen
    pkgs.parted       # For parted (verification)
  ];

  # Pass values from Nix to the shell script's environment.
  # These become shell environment variables.
  env = {
    # Store paths of the input files
    IDBLOADER_FILE_PATH_ENV = ubootIdbloaderFile;
    ITB_FILE_PATH_ENV = ubootItbFile;
    ROOTFS_IMAGE_FILE_PATH_ENV = nixosRootfsImageFile;

    # Calculated values (Nix converts numbers to strings for env vars)
    ROOTFS_START_SECTORS_ENV = builtins.toString rootfsPartitionStartSectors;
  };

  phases = [ "buildPhase" "installPhase" ];

  buildPhase = ''
    set -xe # Exit on error, print commands executed

    # Assign environment variables to local shell variables for clarity/brevity
    local idbloader_file="$IDBLOADER_FILE_PATH_ENV"
    local itb_file="$ITB_FILE_PATH_ENV"
    local rootfs_img_file="$ROOTFS_IMAGE_FILE_PATH_ENV"
    local rootfs_start_sectors="$ROOTFS_START_SECTORS_ENV" # This is a string

    echo "--- Input Files (resolved paths in sandbox) ---"
    echo "IDBloader: $idbloader_file (Size: '$(${pkgs.coreutils}/bin/stat -c %s "$idbloader_file")' bytes)"
    echo "U-Boot ITB: $itb_file (Size: '$(${pkgs.coreutils}/bin/stat -c %s "$itb_file")' bytes)"
    echo "NixOS RootFS: $rootfs_img_file (Size: '$(${pkgs.coreutils}/bin/stat -c %s "$rootfs_img_file")' bytes)"

    local rootfs_img_size_bytes=$(${pkgs.coreutils}/bin/stat -c %s "$rootfs_img_file")
    # Ensure shell arithmetic for division
    local rootfs_img_sectors=$(($rootfs_img_size_bytes / 512))

    # Use bash arithmetic conditional
    if (( $rootfs_img_sectors <= 0 )); then
      echo "Error: RootFS image size is zero or invalid ($rootfs_img_sectors sectors)."
      exit 1
    fi

    echo "--- Image Layout Configuration ---"
    echo "RootFS Partition will start at sector: $rootfs_start_sectors (${builtins.toString rootfsPartitionStartMiB} MiB)"
    echo "RootFS Image Size: $rootfs_img_size_bytes bytes ($rootfs_img_sectors sectors)"

    # Calculate total image size using shell arithmetic
    # rootfs_start_sectors is a shell variable (string, but arithmetic context handles it)
    local rootfs_start_bytes_sh=$(($rootfs_start_sectors * 512))
    local total_img_size_bytes_unaligned=$(($rootfs_start_bytes_sh + $rootfs_img_size_bytes))

    # Align total size to the next MiB for cleanliness
    local alignment_unit_bytes=$((1 * 1024 * 1024)) # This is a shell constant
    local total_img_size_bytes=$(( (( $total_img_size_bytes_unaligned + $alignment_unit_bytes - 1) / $alignment_unit_bytes ) * $alignment_unit_bytes ))
    local total_img_sectors=$(($total_img_size_bytes / 512))

    local final_img_name="nixos-e52c-final.img" # Shell variable

    echo "--- Assembling Final Image: $final_img_name ---"
    echo "Final Image Total Size: $total_img_size_bytes bytes ($total_img_sectors sectors)"

    echo "[INFO] 1. Creating empty sparse image file: $final_img_name"
    "${pkgs.coreutils}/bin/truncate" -s "$total_img_size_bytes" "$final_img_name"

    echo "[INFO] 2. Writing idbloader.img (SPL) to LBA 64..."
    "${pkgs.coreutils}/bin/dd" if="$idbloader_file" of="$final_img_name" seek=64 conv=notrunc,fsync bs=512 status=progress

    echo "[INFO] 3. Writing u-boot.itb (Main U-Boot) to LBA 16384..."
    "${pkgs.coreutils}/bin/dd" if="$itb_file" of="$final_img_name" seek=16384 conv=notrunc,fsync bs=512 status=progress

    echo "[INFO] 4. Creating GPT partition table on $final_img_name..."
    # rootfs_start_sectors and rootfs_img_sectors are shell variables derived above
    local rootfs_partition_end_sector=$(($rootfs_start_sectors + $rootfs_img_sectors - 1))
    local img_last_lba_for_sfdisk=$(($total_img_sectors - 1))

    if (( $rootfs_partition_end_sector > $img_last_lba_for_sfdisk )); then
      echo "Error: Calculated rootfs partition end sector ($rootfs_partition_end_sector) exceeds image last LBA ($img_last_lba_for_sfdisk)."
      exit 1
    fi

    # Using heredoc for sfdisk input.
    # Command substitution '$()' is processed by the shell.
    "${pkgs.util-linux}/bin/sfdisk" "$final_img_name" << EOF
label: gpt
unit: sectors
first-lba: 34
last-lba: $img_last_lba_for_sfdisk

name="NIXOS_ROOT", start=$rootfs_start_sectors, size=$rootfs_img_sectors, type="0FC63DAF-8483-4772-8E79-3D69D8477DE4", uuid="$(${pkgs.util-linux}/bin/uuidgen)"
EOF

    echo "[INFO] Partition table created. Verifying..."
    # Use --no-tell-kernel with --verify if running in a sandbox where kernel can't be told
    "${pkgs.util-linux}/bin/sfdisk" --verify --no-tell-kernel "$final_img_name" || echo "[WARNING] sfdisk verification reported issues. Inspect output."
    "${pkgs.util-linux}/bin/sfdisk" -l "$final_img_name"
    "${pkgs.parted}/bin/parted" -s "$final_img_name" print

    echo "[INFO] 5. Writing NixOS rootfs image into its partition space (starting at sector $rootfs_start_sectors)..."
    "${pkgs.coreutils}/bin/dd" if="$rootfs_img_file" of="$final_img_name" seek="$rootfs_start_sectors" conv=notrunc,fsync bs=512 status=progress

    echo "--- Final monolithic image created: $final_img_name ---"
  ''; # End of buildPhase

  installPhase = ''
    mkdir -p $out # $out is a Nix variable for the output path.
    mv nixos-e52c-final.img $out/nixos-e52c-final.img
    # Optional: Compress the final image
    # echo "Compressing final image..."
    # ${pkgs.xz}/bin/xz -T0 -c $out/nixos-e52c-final.img > $out/nixos-e52c-final.img.xz
    # rm $out/nixos-e52c-final.img # If you only want the compressed version
  '';
}
