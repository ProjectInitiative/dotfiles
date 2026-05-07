#!/usr/bin/env bash
set -euo pipefail

HOSTNAME="${1:?Usage: gen-host-key <hostname>}"
KEY_DIR="$(pwd)/keys/$HOSTNAME"

if [ -f "$KEY_DIR/ssh_host_ed25519_key" ]; then
  echo "Error: Key already exists at $KEY_DIR/ssh_host_ed25519_key" >&2
  echo "Remove it first or choose a different hostname." >&2
  exit 1
fi

mkdir -p "$KEY_DIR"
ssh-keygen -t ed25519 -N "" -f "$KEY_DIR/ssh_host_ed25519_key" -C "root@$HOSTNAME" >&2

echo "" >&2
echo "Keys generated in $KEY_DIR" >&2
echo "" >&2

AGE_KEY=$(ssh-to-age -i "$KEY_DIR/ssh_host_ed25519_key.pub")

echo "Age public key for $HOSTNAME:"
echo "  $AGE_KEY"
echo ""
echo "Add this to .sops.yaml under the host's key_groups[].age:"
echo "  - &ssh_$HOSTNAME $AGE_KEY"
