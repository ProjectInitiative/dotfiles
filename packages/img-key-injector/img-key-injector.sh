#!/usr/bin/env bash
set -euo pipefail

print_help() {
  cat <<EOF
Usage: $(basename "$0") <image> <keydir>

Injects pre-generated SSH host keys into a NixOS disk image using guestfish.

Arguments:
  <image>   Path to the NixOS image file (e.g. nixos-sd-image.img)
  <keydir>  Directory containing ssh_host_*_key and ssh_host_*_key.pub files

Supported key types:
  - ed25519
  - rsa
  - ecdsa
  - dsa (legacy)

Example:
  $(basename "$0") ./nixos-sd-image.img ./keys/

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

IMAGE="$1"
KEYDIR="$2"

if [[ ! -f "$IMAGE" ]]; then
  echo "❌ Error: image not found: $IMAGE"
  exit 1
fi

# Detect root partition (assumes ext4 root)
ROOT_PART=$(guestfish -a "$IMAGE" run : list-filesystems | awk '$2 == "ext4" {print $1; exit}')

if [[ -z "$ROOT_PART" ]]; then
  echo "❌ Could not detect an ext4 root partition in $IMAGE"
  exit 1
fi

echo "ℹ️  Detected root partition: $ROOT_PART"

# Build guestfish script dynamically
GFSCRIPT=$(mktemp)
cleanup() { rm -f "$GFSCRIPT"; }
trap cleanup EXIT

for key in ed25519 rsa ecdsa dsa; do
  priv="$KEYDIR/ssh_host_${key}_key"
  pub="$KEYDIR/ssh_host_${key}_key.pub"

  if [[ -f "$priv" && -f "$pub" ]]; then
    echo "  • Injecting $key key"
    cat >> "$GFSCRIPT" <<EOF
upload $priv /etc/ssh/ssh_host_${key}_key
upload $pub /etc/ssh/ssh_host_${key}_key.pub
chmod 600 /etc/ssh/ssh_host_${key}_key
chmod 644 /etc/ssh/ssh_host_${key}_key.pub
EOF
  fi
done

if [[ ! -s "$GFSCRIPT" ]]; then
  echo "❌ No supported SSH host keys found in $KEYDIR"
  exit 1
fi

guestfish --rw -a "$IMAGE" -m "$ROOT_PART" < "$GFSCRIPT"

echo "✅ Keys injected successfully into $IMAGE"
