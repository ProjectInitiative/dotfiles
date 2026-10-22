#!/usr/bin/env bash
# argo-image-key-inject — bake a stable SSH host key into the argo estate
# image before upload, so VM re-imports keep the same host key (and thus
# the same sops age recipient). Fixes the "new key per re-import" trap in
# OQ-0041: the make-disk-image finalize boot does NOT persist /etc/ssh
# host keys (verified: the garage qcow2's /etc/ssh has no host keys).
#
# Key material lives in OpenBao at k8s/argo/ssh-host-key
# (fields: ed25519_private, ed25519_public). First run generates + stores;
# later runs reuse. Requires an authenticated `bao` (run `bao auth` first).
#
# Usage:
#   argo-image-key-inject <image.qcow2> [--upload]
#
#   <image.qcow2>  the built estate image (kubevirtConfigurations.argo-image)
#   --upload       also compress + upload to garage s3://iso/nixos-estate.qcow2
#
# After injecting, add the printed age pubkey to .sops.yaml as &ssh_argo
# and run `sops updatekeys` ONCE — it never needs repeating while this
# key stays in bao.

set -euo pipefail

BAO_PATH="k8s/argo/ssh-host-key"
GARAGE_ENDPOINT="http://100.90.143.3:3900"
GARAGE_BUCKET="s3://iso/nixos-estate.qcow2"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

IMG="${1:?usage: argo-image-key-inject <image.qcow2> [--upload]}"
MODE="${2:-}"

command -v bao >/dev/null || { echo "ERROR: bao not in PATH (authenticate with: bao auth)"; exit 1; }
command -v guestfish >/dev/null || { echo "ERROR: guestfish not in PATH (nix shell nixpkgs#libguestfs-with-appliance nixpkgs#guestfs-tools)"; exit 1; }
export LIBGUESTFS_BACKEND=direct

# ── 1. Fetch or generate the key pair in OpenBao ─────────────────────────
if ! bao kv get -field=ed25519_private "$BAO_PATH" > "$WORK/id_ed25519" 2>/dev/null; then
  echo "no key in bao at $BAO_PATH — generating and storing"
  ssh-keygen -t ed25519 -N "" -C "argo-vm-host-key" -f "$WORK/generated" -q
  bao kv put "$BAO_PATH" \
    "ed25519_private=@$WORK/generated" \
    "ed25519_public=@$WORK/generated.pub" >/dev/null
  cp "$WORK/generated" "$WORK/id_ed25519"
  cp "$WORK/generated.pub" "$WORK/id_ed25519.pub"
fi
# ensure the pub half exists in bao (older entries may lack it)
if ! bao kv get -field=ed25519_public "$BAO_PATH" > "$WORK/id_ed25519.pub" 2>/dev/null; then
  ssh-keygen -y -f "$WORK/id_ed25519" > "$WORK/id_ed25519.pub"
  bao kv put "$BAO_PATH" \
    "ed25519_private=@$WORK/id_ed25519" \
    "ed25519_public=@$WORK/id_ed25519.pub" >/dev/null
fi
chmod 600 "$WORK/id_ed25519"

# ── 2. Inject into the image ─────────────────────────────────────────────
echo "injecting host key into $(basename "$IMG") ..."
guestfish -a "$IMG" <<EOF
run
mount /dev/sda1 /
mkdir-p /etc/ssh
upload "$WORK/id_ed25519" /etc/ssh/ssh_host_ed25519_key
upload "$WORK/id_ed25519.pub" /etc/ssh/ssh_host_ed25519_key.pub
chmod 0600 /etc/ssh/ssh_host_ed25519_key
chmod 0644 /etc/ssh/ssh_host_ed25519_key.pub
EOF

# ── 3. Verify ────────────────────────────────────────────────────────────
GOT=$(guestfish --ro -a "$IMG" run : mount /dev/sda1 / : cat /etc/ssh/ssh_host_ed25519_key.pub)
WANT=$(cat "$WORK/id_ed25519.pub")
[ "$GOT" = "$WANT" ] || { echo "ERROR: verification mismatch"; exit 1; }

AGE_PUB=$(ssh-to-age < "$WORK/id_ed25519.pub")
echo "OK — baked key fingerprint:"
ssh-keygen -lf "$WORK/id_ed25519.pub"
echo "age recipient (one-time .sops.yaml enrollment as &ssh_argo):"
echo "  $AGE_PUB"

# ── 4. Optional: compress + upload to garage ─────────────────────────────
if [ "$MODE" = "--upload" ]; then
  echo "compressing (qemu-img convert -c) ..."
  qemu-img convert -c -O qcow2 "$IMG" "$WORK/nixos-estate.qcow2"
  echo "uploading to $GARAGE_BUCKET ..."
  if [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
    AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}" aws \
      --endpoint-url "$GARAGE_ENDPOINT" s3 cp "$WORK/nixos-estate.qcow2" "$GARAGE_BUCKET"
  else
    # fall back to the argo-s3-creds secret via kubectl (dev node is a cluster member)
    AKID=$(kubectl -n argo get secret argo-s3-creds -o jsonpath='{.data.accessKeyId}' | base64 -d)
    SKEY=$(kubectl -n argo get secret argo-s3-creds -o jsonpath='{.data.secretKey}' | base64 -d)
    AWS_ACCESS_KEY_ID="$AKID" AWS_SECRET_ACCESS_KEY="$SKEY" AWS_DEFAULT_REGION=us-east-1 \
      aws --endpoint-url "$GARAGE_ENDPOINT" s3 cp "$WORK/nixos-estate.qcow2" "$GARAGE_BUCKET"
  fi
  echo "uploaded. delete the VMI + argo-root DV to re-import (finalizer force-remove may be needed — see RISK-0031)."
fi
