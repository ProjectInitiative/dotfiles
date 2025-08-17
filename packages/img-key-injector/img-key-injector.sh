#!/usr/bin/env bash
set -euo pipefail

print_help() {
  cat <<EOF
Usage: $(basename "$0") <image> <keydir>
Injects pre-generated SSH host keys into a NixOS disk image using loop mounting.
Arguments:
  <image>   Path to the NixOS image file (e.g. nixos-sd-image.img)
  <keydir>  Directory containing ssh_host_*_key and ssh_host_*_key.pub files

Supported key types:
  - ed25519
  - rsa
  - ecdsa
  - dsa (legacy)

Requirements:
  - Must be run as root (for loop mounting)
  - parted and mount utilities

Example:
  sudo $(basename "$0") ./nixos-sd-image.img ./keys/
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_help
  exit 0
fi

if [[ $# -ne 2 ]]; then
  echo "❌ Error: wrong number of arguments"
  print_help
  exit 1
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "❌ Error: this script must be run as root for loop mounting"
  echo "Please run with sudo"
  exit 1
fi

IMAGE="$1"
KEYDIR="$2"

if [[ ! -f "$IMAGE" ]]; then
  echo "❌ Error: image not found: $IMAGE"
  exit 1
fi

if [[ ! -d "$KEYDIR" ]]; then
  echo "❌ Error: key directory not found: $KEYDIR"
  exit 1
fi

# Create a temporary mount point
MOUNT_POINT=$(mktemp -d)
LOOP_DEVICE=""

cleanup() {
  if [[ -n "$LOOP_DEVICE" ]] && losetup "$LOOP_DEVICE" >/dev/null 2>&1; then
    echo "ℹ️  Unmounting and detaching loop device..."
    umount "$MOUNT_POINT" 2>/dev/null || true
    losetup -d "$LOOP_DEVICE" 2>/dev/null || true
  fi
  rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

# Set up loop device for the image
echo "ℹ️  Setting up loop device for $IMAGE"
LOOP_DEVICE=$(losetup -f --show "$IMAGE")
echo "ℹ️  Loop device: $LOOP_DEVICE"

# Use partprobe to ensure kernel sees partitions
partprobe "$LOOP_DEVICE" 2>/dev/null || true

# Find the root partition (look for ext4 filesystem)
ROOT_PARTITION=""
EXT4_PARTITIONS=()

# First, collect all ext4 partitions
for part in "${LOOP_DEVICE}"p*; do
  if [[ -b "$part" ]]; then
    FS_TYPE=$(blkid -o value -s TYPE "$part" 2>/dev/null || echo "unknown")
    if [[ "$FS_TYPE" == "ext4" ]]; then
      EXT4_PARTITIONS+=("$part")
    fi
  fi
done

# Try to find the root partition among ext4 partitions
for part in "${EXT4_PARTITIONS[@]}"; do
  TEMP_MOUNT=$(mktemp -d)
  if mount -o ro "$part" "$TEMP_MOUNT" 2>/dev/null; then
    # Check for root filesystem indicators (be more flexible)
    if [[ -d "$TEMP_MOUNT/etc" ]] || [[ -d "$TEMP_MOUNT/nix" ]] || [[ -d "$TEMP_MOUNT/usr" ]]; then
      ROOT_PARTITION="$part"
      umount "$TEMP_MOUNT"
      rmdir "$TEMP_MOUNT"
      break
    fi
    umount "$TEMP_MOUNT"
  fi
  rmdir "$TEMP_MOUNT"
done

# If we still haven't found it, but there's only one ext4 partition, use it
if [[ -z "$ROOT_PARTITION" && ${#EXT4_PARTITIONS[@]} -eq 1 ]]; then
  echo "ℹ️  Only one ext4 partition found, assuming it's the root partition"
  ROOT_PARTITION="${EXT4_PARTITIONS[0]}"
fi

if [[ -z "$ROOT_PARTITION" ]]; then
  echo "❌ Could not detect an ext4 root partition in $IMAGE"
  echo "Available partitions:"
  for part in "${LOOP_DEVICE}"p*; do
    if [[ -b "$part" ]]; then
      FS_TYPE=$(blkid -o value -s TYPE "$part" 2>/dev/null || echo "unknown")
      echo "  $part: $FS_TYPE"
    fi
  done
  exit 1
fi

echo "ℹ️  Detected root partition: $ROOT_PARTITION"

# Mount the root partition
echo "ℹ️  Mounting root partition..."
mount "$ROOT_PARTITION" "$MOUNT_POINT"

# Check if /etc/ssh directory exists, create if it doesn't
SSH_DIR="$MOUNT_POINT/etc/ssh"
if [[ ! -d "$SSH_DIR" ]]; then
  echo "ℹ️  Creating /etc/ssh directory"
  mkdir -p "$SSH_DIR"
  chmod 755 "$SSH_DIR"
fi

# Inject SSH host keys
KEYS_INJECTED=0
for key in ed25519 rsa ecdsa dsa; do
  priv="$KEYDIR/ssh_host_${key}_key"
  pub="$KEYDIR/ssh_host_${key}_key.pub"
  
  if [[ -f "$priv" && -f "$pub" ]]; then
    echo "  • Injecting $key key"
    cp "$priv" "$SSH_DIR/ssh_host_${key}_key"
    cp "$pub" "$SSH_DIR/ssh_host_${key}_key.pub"
    chmod 600 "$SSH_DIR/ssh_host_${key}_key"
    chmod 644 "$SSH_DIR/ssh_host_${key}_key.pub"
    chown root:root "$SSH_DIR/ssh_host_${key}_key"
    chown root:root "$SSH_DIR/ssh_host_${key}_key.pub"
    KEYS_INJECTED=$((KEYS_INJECTED + 1))
  fi
done

if [[ $KEYS_INJECTED -eq 0 ]]; then
  echo "❌ No supported SSH host keys found in $KEYDIR"
  echo "Expected files: ssh_host_{ed25519,rsa,ecdsa,dsa}_key[.pub]"
  exit 1
fi

echo "✅ $KEYS_INJECTED key(s) injected successfully into $IMAGE"
