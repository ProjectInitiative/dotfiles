# make-fat-fs.nix
# Builds a VFAT (FAT32) image containing specified Nix store paths
# and populated files. The image is created with a fixed size.
{
  pkgs,
  lib,
  # List of derivations to be included (their closures)
  storePaths,
  # Size of the VFAT image (e.g., "256M", "1G"). Required.
  size,
  # Volume label for the VFAT filesystem (max 11 characters).
  volumeLabel ? "VFAT_BOOT",
  # Volume ID (32-bit hex number). Auto-generated if null.
  volumeID ? null, # Example: "aabbccdd"
  # Whether or not to compress the resulting image with zstd
  compressImage ? false,
  # Shell commands to populate the ./files directory.
  # All files in that directory are copied to the root of the VFAT FS.
  populateImageCommands ? "",
  # Dependencies (explicitly passed for clarity, could also use pkgs directly)
  dosfstools ? pkgs.dosfstools,
  mtools ? pkgs.mtools,
  coreutils ? pkgs.coreutils, # For du, truncate, basename, etc.
  findutils ? pkgs.findutils, # For find
  gnused ? pkgs.gnused, # For sed
  gawk ? pkgs.gawk, # For awk
  libfaketime ? pkgs.libfaketime,
  zstd ? pkgs.zstd,
}:

let
  sdClosureInfo = pkgs.buildPackages.closureInfo { rootPaths = storePaths; };

  # Parse size string (e.g., "256M", "1G") into bytes. Basic implementation.
  # More robust parsing could be added if needed.
  sizeInBytes = builtins.readFile (pkgs.runCommand "size-in-bytes" { SIZE_STR=size; } ''
    SIZE_STR="$SIZE_STR"
    SIZE_VAL=$(echo "$SIZE_STR" | sed 's/[KMGTP]$//i')
    UNIT=$(echo "$SIZE_STR" | sed 's/^[0-9]*//i' | tr '[:lower:]' '[:upper:]')
    FACTOR=1
    case "$UNIT" in
        K) FACTOR=1024 ;;
        M) FACTOR=$((1024*1024)) ;;
        G) FACTOR=$((1024*1024*1024)) ;;
        T) FACTOR=$((1024*1024*1024*1024)) ;;
        P) FACTOR=$((1024*1024*1024*1024*1024)) ;;
        "") FACTOR=1 ;; # Assume bytes if no unit
        *) echo "Error: Unknown size unit '$UNIT' in '$SIZE_STR'" >&2; exit 1 ;;
    esac
    # Use awk for potentially large number arithmetic
    echo "$SIZE_VAL $FACTOR" | ${gawk}/bin/awk '{printf "%.0f", $1 * $2}' > $out
  '');


in
pkgs.stdenv.mkDerivation {
  name = "vfat-${volumeLabel}.img";

  nativeBuildInputs = [
    dosfstools
    mtools
    coreutils
    findutils
    gnused
    gawk
    libfaketime
  ] ++ lib.optional compressImage zstd;

  # Pass derived values via environment vars
  IMG_SIZE_BYTES = sizeInBytes;
  VOLUME_LABEL = volumeLabel;
  VOLUME_ID = volumeID; # Can be empty string if null

  # Note: We don't need fakeroot as VFAT doesn't store POSIX permissions.

  buildCommand = ''
    set -e
    echo "--- Starting make-fat-fs buildCommand ---"

    # Internal filename consistency, used only for temporary compressed path
    local img_file_name="fat32-fs.img"
    local img_path # Path to the image file being worked on

    if ${if compressImage then "true" else "false"}; then
        # Compressed case: $out is the final compressed file path
        img_path="./''${img_file_name}" # Temporary working file
        # Ensure temporary file exists
        touch "$img_path"
        echo "Working on temporary image: $img_path, will compress to final output path: $out"
    else
        # --- CHANGE: Non-compressed case: $out IS the final image file path ---
        img_path="$out" # $out is the target file path
        # Ensure the directory containing $out exists
        # Nix usually handles creating the $out directory itself if needed,
        # but touching the file requires the dir.
        mkdir -p "$(dirname "$out")"
        # Ensure the target file exists for truncate/mkfs.vfat
        touch "$img_path"
        echo "Working directly on final image file path: $img_path"
    fi

    local target_size_bytes="$IMG_SIZE_BYTES"
    local vol_label="$VOLUME_LABEL"
    local vol_id="$VOLUME_ID"

    if [ -z "$target_size_bytes" ] || [ "$target_size_bytes" -le 0 ]; then
      echo "Error: Calculated image size ($target_size_bytes bytes) is invalid."
      exit 1
    fi

    echo "Target image size: $target_size_bytes bytes"
    echo "Volume Label: $vol_label"
    echo "Volume ID: ''${vol_id:-<auto>}" # Show <auto> if empty

    # 1. Create the empty image file of the target size
    echo "Creating empty image file: $img_path"
    truncate -s "$target_size_bytes" "$img_path"

    # 2. Format the image file as FAT32
    echo "Formatting image as FAT32..."
    local mkfs_opts="-F 32 -I" # Force FAT32, allow format on non-block-device
    if [ -n "$vol_label" ]; then
      mkfs_opts="$mkfs_opts -n $vol_label"
    fi
    if [ -n "$vol_id" ]; then
      mkfs_opts="$mkfs_opts -i $vol_id"
    fi
    # Use faketime for deterministic filesystem creation time/volume ID generation
    faketime -f "1970-01-01 00:00:01" mkfs.vfat $mkfs_opts "$img_path"

    # 3. Prepare the source directory structure (`./rootImage`)
    echo "Preparing source files..."
    mkdir -p ./rootImage

    # Run user-provided commands to populate ./files
    (
      mkdir -p ./files
      ${populateImageCommands}
    )

    # Copy Nix store paths (dereference symlinks as FAT doesn't support them)
    # Check if there are any store paths to copy
    if [ -s "${sdClosureInfo}/store-paths" ]; then
      echo "Copying Nix store paths (dereferencing links)..."
      # Create nix/store structure if needed (usually not for boot partitions)
      # mkdir -p ./rootImage/nix/store # Uncomment if needed
      # Copy paths listed in closureInfo to the root of './rootImage'
      xargs -I % cp -aL --reflink=auto % -t ./rootImage/ < ${sdClosureInfo}/store-paths
    else
        echo "No Nix store paths specified to copy."
    fi


    # Copy files populated by populateImageCommands
    # Need to handle potential name collisions carefully if store paths are also copied to root
    echo "Copying files from ./files directory..."
    (
      # Set options for reliable copying, including hidden files
      shopt -s dotglob nullglob
      local file_count=$(find ./files -mindepth 1 -print -quit | wc -l)
      if [ "$file_count" -gt 0 ]; then
          cp -arT --reflink=auto ./files/ ./rootImage/
      else
          echo "No files found in ./files to copy."
      fi
      shopt -u dotglob nullglob
    )


    # 4. Copy files from `./rootImage` into the VFAT image using mtools
    echo "Populating VFAT image using mtools..."
    # Ensure mtools uses deterministic timestamps
    export MTOOLS_SKIP_CHECK=1 # Avoid "device partition exceeds disk size" heuristic checks
    export MTOOLSRC=/dev/null # Avoid reading user config

    # Create directories first, sorted for determinism
    # Need to cd into rootImage to get relative paths for mtools
    (
      cd ./rootImage
      # Find directories (excluding the root '.') and sort them
      find . -mindepth 1 -type d -printf '%P\n' | sort | while IFS= read -r dir; do
        echo "Creating directory in VFAT: ::/$dir"
        # Use faketime around each mtools command
        faketime -f "1970-01-01 00:00:01" mmd -i "$img_path" "::/$dir"
      done

      # Copy files next, sorted for determinism
      find . -type f -printf '%P\n' | sort | while IFS= read -r file; do
        echo "Copying file to VFAT: ::/$file"
        # Use faketime around each mtools command
        # -p: Attempt to preserve modification time (within VFAT limits)
        # -m: Attempt to preserve mode (limited effect on VFAT)
        faketime -f "1970-01-01 00:00:01" mcopy -p -m -i "$img_path" "$file" "::/$file"
      done
    )


    # 5. Verify the filesystem
    echo "Verifying VFAT filesystem..."
    # Use -v for verbose, -n for non-interactive check
    fsck.vfat -v -n "$img_path" || { echo "--- fsck.vfat check failed! ---"; exit 1; }

    # 6. Final Steps (Compression or Moving)
    echo "--- Verifying size of resulting image file ($img_path) ---"
    ls -lh "$img_path" || echo "ls failed"
    stat "$img_path" || echo "stat failed"
    echo "--- End verification ---"

    if ${if compressImage then "true" else "false"}; then
        echo "Compressing temporary image $img_path to final output path $out ..."
        zstd -T$NIX_BUILD_CORES -v --no-progress "$img_path" -o "$out"
        echo "--- Verifying size of final compressed file ($out) ---"
        ls -lh "$out" || echo "ls failed on compressed $out"
        rm "$img_path" # Clean up temporary uncompressed file
    else
        # --- CHANGE: No move needed, $img_path is already $out ---
        echo "--- Final uncompressed image is $img_path (which is the final output path $out) ---"
        # Optional verification if needed
        if [ -f "$out" ]; then
            echo "Final file exists: $out"
            ls -lh "$out" || echo "ls failed on final $out"
        else
            echo "Error: Final output file $out not found!"
            exit 1
        fi
    fi

    echo "--- Finishing make-fat-fs buildCommand ---"
  '';
}

