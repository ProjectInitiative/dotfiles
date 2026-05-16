#!/usr/bin/env bash
set -euo pipefail

print_help() {
  cat <<EOF
Usage: $(basename "$0") mount <image>
       $(basename "$0") umount <image> <mount_point> [--retar]

Mount or unmount a NixOS image. Supports:
  .img         - Raw disk images (via loop device)
  .tar.gz/.tgz - Compressed tarballs (extracted to temp directory)
  .tar         - Uncompressed tarballs

Commands:
  mount   Mount/extract the image and print the mount point path to stdout
  umount  Unmount/detach and clean up. For tarballs, pass --retar to re-pack.

Examples:
  MOUNT=\$(sudo nixos-image-mount mount nixos-rockchip-full.img)
  sudo nixos-image-mount umount nixos-rockchip-full.img "\$MOUNT"

  MOUNT=\$(nixos-image-mount mount nixos-image.tar.gz)
  nixos-image-mount umount nixos-image.tar.gz "\$MOUNT" --retar
EOF
}

die() { echo "Error: $*" >&2; exit 1; }

is_tar() {
  local f=$1
  [[ $f == *.tar.gz || $f == *.tgz || $f == *.tar ]]
}

is_img() {
  local f=$1
  [[ $f == *.img || $f == *.raw ]]
}

detect_type() {
  local f=$1
  if is_tar "$f"; then echo tar
  elif is_img "$f"; then echo img
  else die "Unsupported image type: $f (expected .img, .raw, .tar.gz, .tgz, or .tar)"
  fi
}

cmd_mount() {
  local image=$1
  [[ -f $image ]] || die "Image not found: $image"

  image=$(realpath "$image")
  local img_type
  img_type=$(detect_type "$image")
  local mount_point
  mount_point=$(mktemp -d "/tmp/nixos-image-mount.XXXXXX")

  if [[ $img_type == tar ]]; then
    echo "Extracting $image -> $mount_point" >&2
    if [[ $image == *.tar.gz || $image == *.tgz ]]; then
      tar -xzf "$image" -C "$mount_point"
    else
      tar -xf "$image" -C "$mount_point"
    fi
    echo "$mount_point"

  elif [[ $img_type == img ]]; then
    [[ $EUID -eq 0 ]] || die "Must be root to mount .img files"

    echo "Setting up loop device for $image ..." >&2
    local loop_device
    loop_device=$(losetup -f --show "$image")

    local mount_ok=false
    cleanup() { $mount_ok || losetup -d "$loop_device" 2>/dev/null || true; }
    trap cleanup EXIT

    partprobe "$loop_device" 2>/dev/null || true
    sleep 0.5

    local root_part=""
    for part in "${loop_device}"p*; do
      [[ -b $part ]] || continue
      local fstype
      fstype=$(blkid -o value -s TYPE "$part" 2>/dev/null || echo "")
      [[ $fstype == ext4 ]] || continue

      local tmpmnt
      tmpmnt=$(mktemp -d)
      if mount -o ro "$part" "$tmpmnt" 2>/dev/null; then
        if [[ -d $tmpmnt/etc || -d $tmpmnt/nix || -d $tmpmnt/usr ]]; then
          root_part=$part
          umount "$tmpmnt" 2>/dev/null || true
          rmdir "$tmpmnt" 2>/dev/null || true
          break
        fi
        umount "$tmpmnt" 2>/dev/null || true
      fi
      rmdir "$tmpmnt" 2>/dev/null || true
    done

    [[ -n $root_part ]] || die "Could not detect root partition in $image"

    mount "$root_part" "$mount_point"
    mount_ok=true
    trap - EXIT

    echo "$mount_point"
  fi
}

cmd_umount() {
  local image=$1
  local mount_point=$2
  local retar=${3:-}

  [[ -d $mount_point ]] || die "Mount point not found: $mount_point"

  image=$(realpath "$image")
  local img_type
  img_type=$(detect_type "$image")

  if [[ $img_type == img ]]; then
    [[ $EUID -eq 0 ]] || die "Must be root to unmount .img files"

    echo "Unmounting $mount_point ..." >&2
    umount "$mount_point"

    local loop_device
    loop_device=$(losetup -j "$image" -O NAME -n 2>/dev/null | head -1 || true)
    if [[ -n $loop_device ]]; then
      echo "Detaching loop device $loop_device ..." >&2
      losetup -d "$loop_device"
    fi

    rmdir "$mount_point" 2>/dev/null || true

  elif [[ $img_type == tar ]]; then
    if [[ $retar == --retar ]]; then
      echo "Re-packaging tarball ..." >&2
      local tmparchive
      tmparchive=$(mktemp "/tmp/nixos-image-mount-retar.XXXXXX")
      if [[ $image == *.tar.gz || $image == *.tgz ]]; then
        tar -czf "$tmparchive" -C "$mount_point" .
      else
        tar -cf "$tmparchive" -C "$mount_point" .
      fi
      mv "$tmparchive" "$image"
    fi

    echo "Cleaning up $mount_point ..." >&2
    rm -rf "$mount_point"
  fi
}

case "${1:-}" in
  mount)  cmd_mount "${2:?Missing image argument}" ;;
  umount) cmd_umount "${2:?Missing image argument}" "${3:?Missing mount point argument}" "${4:-}" ;;
  -h|--help|"") print_help ;;
  *) die "Unknown command: $1 (use -h for help)" ;;
esac
