# Builds an ext4 image containing a populated /nix/store with the closure
# of store paths passed in the storePaths parameter, in addition to the
# contents of a directory that can be populated with commands. The
# generated image is sized to only fit its contents, with the expectation
# that a script resizes the filesystem at boot time.
# --- MODIFIED VERSION: Includes file truncation after resize ---
{
  pkgs,
  lib,
  # List of derivations to be included
  storePaths,
  # Whether or not to compress the resulting image with zstd
  compressImage ? false,
  zstd,
  # Shell commands to populate the ./files directory.
  # All files in that directory are copied to the root of the FS.
  populateImageCommands ? "",
  volumeLabel,
  uuid ? "44444444-4444-4444-8888-888888888888",
  e2fsprogs,
  libfaketime,
  perl,
  fakeroot,
}:

let
  sdClosureInfo = pkgs.buildPackages.closureInfo { rootPaths = storePaths; };
in
pkgs.stdenv.mkDerivation {
  name = "ext4-fs.img${lib.optionalString compressImage ".zst"}";

  nativeBuildInputs = [
    e2fsprogs.bin
    libfaketime
    perl
    fakeroot
  ] ++ lib.optional compressImage zstd;

  buildCommand = ''
    set -e # Exit immediately if a command exits with a non-zero status.
    echo "--- Starting make-ext4-fs buildCommand ---"

    img_file_name="ext4-rootfs.img" # Define a consistent internal name
    ${if compressImage then "img=$img_file_name" else "img=$out"}

    # Need to handle the case where img IS $out if not compressing
    if [ "$img" != "$out" ]; then
        touch $img # Ensure temp file exists if compressing
    else
        # If not compressing, $img points directly to $out, ensure it exists
        # $out is a directory, so we create the final file path inside it
        img="$out/''${img_file_name}"
        mkdir -p $out
        touch $img
    fi

    (
    mkdir -p ./files
    ${populateImageCommands}
    )

    echo "Preparing store paths for image..."

    # Create nix/store before copying path
    mkdir -p ./rootImage/nix/store

    xargs -I % cp -a --reflink=auto % -t ./rootImage/nix/store/ < ${sdClosureInfo}/store-paths
    (
      GLOBIGNORE=".:.."
      shopt -u dotglob

      for f in ./files/*; do
          cp -a --reflink=auto -t ./rootImage/ "$f"
      done
    )

    # Also include a manifest of the closures in a format suitable for nix-store --load-db
    cp ${sdClosureInfo}/registration ./rootImage/nix-path-registration

    # --- Size calculation, mkfs, resize2fs ---
    numInodes=$(find ./rootImage | wc -l)
    numDataBlocks=$(du -s -c -B 4096 --apparent-size ./rootImage | tail -1 | awk '{ print int($1 * 1.20) }')
    bytes=$((2 * 4096 * $numInodes + 4096 * $numDataBlocks))
    echo "Initial calculated size estimate: $bytes bytes (numInodes=$numInodes, numDataBlocks=$numDataBlocks)"
    mebibyte=$(( 1024 * 1024 ))
    if (( bytes % mebibyte )); then bytes=$(( ( bytes / mebibyte + 1) * mebibyte )); fi
    echo "Rounding up initial size to $bytes bytes"
    truncate -s $bytes $img # Initial truncate based on estimation
    faketime -f "1970-01-01 00:00:01" fakeroot mkfs.ext4 -m 0 -L ${volumeLabel} -U ${uuid} -d ./rootImage $img
    export EXT2FS_NO_MTAB_OK=yes
    fsck.ext4 -n -f $img || { echo "--- Fsck failed after mkfs ---"; exit 1; }
    echo "Shrinking filesystem to minimum size..."
    resize2fs -M $img
    echo "--- Filesystem info after resize2fs -M ---"
    dumpe2fs -h $img || echo "ERROR: dumpe2fs after resize2fs -M failed"
    echo "-------------------------------------------"
    echo "Calculating target size with 16MiB buffer..."
    dumpe2fs_output=$(dumpe2fs -h $img) || { echo "ERROR: dumpe2fs command for target_blocks failed"; exit 1; }
    target_blocks=$(echo "$dumpe2fs_output" | awk -F: '/Block count/{count=$2} /Block size/{size=$2} END{ if (size > 0) { print int((count*size+16*1024*1024)/size + 0.999999) } else { exit 1 } }')
    if [ -z "$target_blocks" ]; then echo "ERROR: Failed to parse target_blocks"; echo "$dumpe2fs_output"; exit 1; fi
    echo "Resizing filesystem to $target_blocks blocks..."
    resize2fs $img $target_blocks
    # --- End Size calculation ---


    # --- Truncate file and VERIFY ---
    echo "Truncating image file to match resized filesystem..."
    dumpe2fs_output_after_resize=$(dumpe2fs -h $img) || { echo "ERROR: dumpe2fs command failed after resize"; exit 1; }
    blockSize=$(echo "$dumpe2fs_output_after_resize" | awk -F: '/Block size/ { print $2 }' | tr -d ' ')
    if [ -z "$blockSize" ] || [ "$blockSize" -le 0 ]; then echo "ERROR: Failed to determine valid blockSize"; echo "$dumpe2fs_output_after_resize"; exit 1; fi
    finalSizeBytes=$((''${target_blocks} * ''${blockSize}))
    if [ -z "$finalSizeBytes" ] || [ "$finalSizeBytes" -le 0 ]; then echo "ERROR: Calculation of finalSizeBytes failed ($target_blocks * $blockSize)"; exit 1; fi

    echo "Final calculated filesystem size is ''${finalSizeBytes} bytes (''${target_blocks} blocks of size ''${blockSize} bytes)."
    echo "Executing: truncate -s ''${finalSizeBytes} ''${img}"
    truncate -s ''${finalSizeBytes} ''${img}
    echo "Truncate command finished."

    echo "--- Verifying size of resulting file ($img) post-truncate ---"
    ls -lh ''${img} || echo "ls failed"
    stat ''${img} || echo "stat failed"
    echo "--- End verification ---"
    # --- End Truncate file ---

    # --- Final Checks and Compression ---
    echo "Performing final fsck check..."
    fsck.ext4 -n -f $img || { echo "--- Fsck failed after final truncation ---"; exit 1; }

    if [ ''${builtins.toString compressImage} ]; then
      echo "Compressing image ''${img} to $out"
      zstd -T$NIX_BUILD_CORES -v --no-progress ''${img} -o $out
      echo "--- Verifying size of final compressed file ($out) ---"
      ls -lh $out || echo "ls failed"
    elif [ "$img" != "$out/''${img_file_name}" ]; then
       # If not compressing, and $img was temporary, move it to $out
       # This case shouldn't happen with the logic at the top now, but as a safeguard
       echo "Moving temporary image ''${img} to final destination $out/''${img_file_name}"
       # Ensure $out exists (it should, based on top logic)
       mkdir -p $out
       mv ''${img} $out/''${img_file_name}
       echo "--- Verifying size of final uncompressed file ($out/''${img_file_name}) ---"
       ls -lh $out/''${img_file_name} || echo "ls failed"
    else
       echo "--- Final uncompressed file is $img ---"
       # Already verified size after truncate
    fi
    echo "--- Finishing make-ext4-fs buildCommand ---"
  '';
}
