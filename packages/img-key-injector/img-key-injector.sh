#!/usr/bin/env bash
set -euo pipefail

print_help() {
  cat <<EOF
Usage: $(basename "$0") [options] <image> [keydir]
Injects SSH host keys into a NixOS disk image.

Supported image types:
  <disk.img>      Partitioned raw disk image (root ext4 partition auto-detected)
  <root_part>     Bare filesystem image (e.g. AVF root_part member, mounted directly)
  <image>.tar.gz  AVF-style archive (only root_part is extracted/modified, then re-packed;
                  no full extraction, no intermediate disk image)

Options:
  -g, --generate        Generate missing host keys into <keydir> before injecting
                        (default keydir: ./keys)
  --key-types LIST      Comma-separated key types to generate (default: ed25519)
  -h, --help            Show this help

Requirements:
  - Must be run as root (for loop mounting)
  - ssh-keygen (for --generate), tar, gzip/pigz, parted, util-linux, e2fsprogs

Examples:
  sudo $(basename "$0") nixos-sd-image.img ./keys/
  sudo $(basename "$0") --generate nixos-sd-image.img
  sudo $(basename "$0") avf_image.tar.gz ~/dotfiles/keys/cutter
  sudo $(basename "$0") --generate --key-types ed25519,rsa root_part ./keys/
EOF
}

die() { echo "❌ Error: $*" >&2; exit 1; }

GENERATE=0
KEY_TYPES="ed25519"
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      print_help
      exit 0
      ;;
    -g|--generate)
      GENERATE=1
      shift
      ;;
    --key-types)
      [[ $# -ge 2 ]] || die "--key-types requires a value"
      KEY_TYPES=$2
      shift 2
      ;;
    -*)
      die "Unknown option: $1 (use -h for help)"
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POSITIONAL[@]} -lt 1 || ${#POSITIONAL[@]} -gt 2 ]]; then
  echo "❌ Error: wrong number of arguments"
  print_help
  exit 1
fi

IMAGE=${POSITIONAL[0]}
KEYDIR=${POSITIONAL[1]:-}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "❌ Error: this script must be run as root for loop mounting"
  echo "Please run with sudo"
  exit 1
fi

if [[ ! -f "$IMAGE" ]]; then
  die "image not found: $IMAGE"
fi

if [[ -z "$KEYDIR" ]]; then
  if [[ $GENERATE -eq 1 ]]; then
    KEYDIR="$PWD/keys"
  else
    die "key directory required (or pass --generate to create keys)"
  fi
fi

IMAGE=$(realpath "$IMAGE")
KEYDIR=$(realpath -m "$KEYDIR")

# ---------------------------------------------------------------- keydir prep

mkdir -p "$KEYDIR"
IFS=',' read -ra KEY_TYPE_LIST <<< "$KEY_TYPES"
for type in "${KEY_TYPE_LIST[@]}"; do
  priv="$KEYDIR/ssh_host_${type}_key"
  if [[ ! -f "$priv" ]]; then
    if [[ $GENERATE -eq 1 ]]; then
      echo "ℹ️  Generating $type host key in $KEYDIR"
      ssh-keygen -q -t "$type" -N "" -f "$priv" -C "img-key-injector"
    else
      echo "⚠️  No $type key found in $KEYDIR (pass --generate to create)"
    fi
  fi
done

if [[ -z "$(command ls "$KEYDIR" 2>/dev/null)" ]]; then
  die "no keys in $KEYDIR and --generate not passed"
fi

# ---------------------------------------------------------------- state/cleanup

MOUNT_POINT=""
LOOP_DEVICE=""
WORKDIR=""
NEW_TARBALL=""

cleanup() {
  if [[ -n "$MOUNT_POINT" ]] && mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "ℹ️  Unmounting $MOUNT_POINT ..."
    umount "$MOUNT_POINT" 2>/dev/null || true
  fi
  if [[ -n "$LOOP_DEVICE" ]] && losetup "$LOOP_DEVICE" >/dev/null 2>&1; then
    losetup -d "$LOOP_DEVICE" 2>/dev/null || true
  fi
  [[ -n "$WORKDIR" ]] && rm -rf "$WORKDIR"
  if [[ -n "$NEW_TARBALL" ]]; then
    rm -f "$NEW_TARBALL"
  fi
}
trap cleanup EXIT

# Mounts $1 (bare fs or partitioned image) at $MOUNT_POINT, sets LOOP_DEVICE
mount_image_file() {
  local file=$1
  MOUNT_POINT=$(mktemp -d)
  LOOP_DEVICE=$(losetup -f --show "$file")
  echo "ℹ️  Loop device: $LOOP_DEVICE"

  local fstype
  fstype=$(blkid -p -o value -s TYPE "$file" 2>/dev/null || true)

  if [[ -n "$fstype" ]]; then
    # Bare filesystem image (no partition table) — mount the whole file
    echo "ℹ️  Bare filesystem image ($fstype), mounting directly"
    mount "$LOOP_DEVICE" "$MOUNT_POINT"
    return
  fi

  # Partitioned image — find the root ext4 partition
  partprobe "$LOOP_DEVICE" 2>/dev/null || true

  ROOT_PARTITION=""
  EXT4_PARTITIONS=()
  for part in "${LOOP_DEVICE}"p*; do
    if [[ -b "$part" ]]; then
      FS_TYPE=$(blkid -o value -s TYPE "$part" 2>/dev/null || echo "unknown")
      if [[ "$FS_TYPE" == "ext4" ]]; then
        EXT4_PARTITIONS+=("$part")
      fi
    fi
  done

  for part in "${EXT4_PARTITIONS[@]}"; do
    TEMP_MOUNT=$(mktemp -d)
    if mount -o ro "$part" "$TEMP_MOUNT" 2>/dev/null; then
      if [[ -d "$TEMP_MOUNT/etc" || -d "$TEMP_MOUNT/nix" || -d "$TEMP_MOUNT/usr" ]]; then
        ROOT_PARTITION="$part"
        umount "$TEMP_MOUNT"
        rmdir "$TEMP_MOUNT"
        break
      fi
      umount "$TEMP_MOUNT"
    fi
    rmdir "$TEMP_MOUNT"
  done

  if [[ -z "$ROOT_PARTITION" && ${#EXT4_PARTITIONS[@]} -eq 1 ]]; then
    echo "ℹ️  Only one ext4 partition found, assuming it's the root partition"
    ROOT_PARTITION="${EXT4_PARTITIONS[0]}"
  fi

  if [[ -z "$ROOT_PARTITION" ]]; then
    echo "❌ Could not detect an ext4 root partition in $file"
    echo "Available partitions:"
    for part in "${LOOP_DEVICE}"p*; do
      [[ -b "$part" ]] || continue
      echo "  $part: $(blkid -o value -s TYPE "$part" 2>/dev/null || echo unknown)"
    done
    exit 1
  fi

  echo "ℹ️  Detected root partition: $ROOT_PARTITION"
  mount "$ROOT_PARTITION" "$MOUNT_POINT"
}

umount_image_file() {
  if [[ -n "$MOUNT_POINT" ]] && mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    umount "$MOUNT_POINT"
  fi
  if [[ -n "$LOOP_DEVICE" ]] && losetup "$LOOP_DEVICE" >/dev/null 2>&1; then
    losetup -d "$LOOP_DEVICE"
  fi
  [[ -n "$MOUNT_POINT" ]] && rmdir "$MOUNT_POINT" 2>/dev/null || true
  MOUNT_POINT=""
  LOOP_DEVICE=""
}

# Copies keys from $KEYDIR into <mountpoint>/etc/ssh
inject_keys() {
  local mount=$1
  local SSH_DIR="$mount/etc/ssh"
  if [[ ! -d "$SSH_DIR" ]]; then
    echo "ℹ️  Creating /etc/ssh directory"
    mkdir -p "$SSH_DIR"
    chmod 755 "$SSH_DIR"
  fi

  local KEYS_INJECTED=0
  for key in ed25519 rsa ecdsa dsa; do
    priv="$KEYDIR/ssh_host_${key}_key"
    pub="$KEYDIR/ssh_host_${key}_key.pub"

    if [[ -f "$priv" && -f "$pub" ]]; then
      echo "  • Injecting $key key"
      install -m 600 -o root -g root "$priv" "$SSH_DIR/ssh_host_${key}_key"
      install -m 644 -o root -g root "$pub" "$SSH_DIR/ssh_host_${key}_key.pub"
      KEYS_INJECTED=$((KEYS_INJECTED + 1))
    fi
  done

  if [[ $KEYS_INJECTED -eq 0 ]]; then
    die "no supported SSH host keys found in $KEYDIR (expected ssh_host_{ed25519,rsa,ecdsa,dsa}_key[.pub])"
  fi
  echo "✅ $KEYS_INJECTED key(s) injected"
}

# ---------------------------------------------------------------- modes

# Case 1: .tar.gz AVF-style archive — extract members, inject root_part, re-pack
if [[ "$IMAGE" == *.tar.gz || "$IMAGE" == *.tgz ]]; then
  echo "ℹ️  Tarball detected: $IMAGE"
  WORKDIR=$(mktemp -d "/tmp/img-key-injector.XXXXXX")
  NEW_TARBALL="$IMAGE.new"

  mapfile -t MEMBERS < <(tar -tzf "$IMAGE")
  if [[ ${#MEMBERS[@]} -eq 0 ]]; then
    die "archive contains no members"
  fi
  if ! printf '%s\n' "${MEMBERS[@]}" | grep -qE '(^|/)root_part$'; then
    die "no 'root_part' member in $IMAGE (members: ${MEMBERS[*]})"
  fi

  echo "ℹ️  Extracting archive members (root_part will be replaced, rest preserved)..."
  # Only streams the gzip once; every member except root_part lands on disk
  tar -xzf "$IMAGE" -C "$WORKDIR" --exclude='root_part'

  echo "ℹ️  Injecting keys into root_part ..."
  mount_image_file "$WORKDIR/root_part"
  inject_keys "$MOUNT_POINT"
  umount_image_file

  echo "ℹ️  Re-packing $IMAGE (single gzip pass) ..."
  for member in "${MEMBERS[@]}"; do
    [[ -e "$WORKDIR/$member" ]] || die "missing member after extraction: $member"
  done
  GZIP_CMD=pigz
  command -v pigz >/dev/null 2>&1 || GZIP_CMD=gzip
  tar -C "$WORKDIR" -cf - "${MEMBERS[@]}" | "$GZIP_CMD" > "$NEW_TARBALL"
  mv "$NEW_TARBALL" "$IMAGE"
  NEW_TARBALL=""
  rm -rf "$WORKDIR"
  WORKDIR=""

  echo "✅ $IMAGE updated in place"
  exit 0
fi

# Case 2: raw file — bare filesystem or partitioned disk image
echo "ℹ️  Setting up loop device for $IMAGE"
mount_image_file "$IMAGE"
inject_keys "$MOUNT_POINT"
umount_image_file
echo "✅ Keys injected successfully into $IMAGE"
