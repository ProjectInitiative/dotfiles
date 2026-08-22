#!/usr/bin/env bash
set -euo pipefail

# Install a minimal, standalone NixOS baseline from a booted live installer.
# This intentionally does not use this repository's flake.

TARGET="${1:-nixos@192.168.1.106}"
DISK="${2:-/dev/nvme0n1}"
INSTALL_HOSTNAME="${3:-sextant}"
INSTALL_USER="${INSTALL_USER:-kylepzak}"
STATE_VERSION="${STATE_VERSION:-26.05}"

if [[ ! "$DISK" =~ ^/dev/[a-zA-Z0-9._/-]+$ ]]; then
  echo "Invalid disk path: $DISK" >&2
  exit 2
fi
if [[ ! "$INSTALL_HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
  echo "Invalid hostname: $INSTALL_HOSTNAME" >&2
  exit 2
fi
if [[ ! "$INSTALL_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "Invalid install user: $INSTALL_USER" >&2
  exit 2
fi
if [[ ! "$STATE_VERSION" =~ ^[0-9]{2}\.[0-9]{2}$ ]]; then
  echo "Invalid STATE_VERSION: $STATE_VERSION" >&2
  exit 2
fi

if [[ -n "${SSH_PUBLIC_KEY:-}" ]]; then
  PUBLIC_KEY="$SSH_PUBLIC_KEY"
elif [[ -r "$HOME/.ssh/id_ed25519.pub" ]]; then
  PUBLIC_KEY="$(<"$HOME/.ssh/id_ed25519.pub")"
else
  PUBLIC_KEY="$(ssh-add -L 2>/dev/null | head -n1 || true)"
fi

# Strip the optional comment so it can be embedded safely in Nix syntax.
PUBLIC_KEY="$(awk '{ print $1 " " $2 }' <<<"$PUBLIC_KEY")"
if [[ ! "$PUBLIC_KEY" =~ ^ssh-[^[:space:]]+[[:space:]][A-Za-z0-9+/=]+$ ]]; then
  echo "Could not find a usable SSH public key." >&2
  echo "Set SSH_PUBLIC_KEY or create ~/.ssh/id_ed25519.pub." >&2
  exit 2
fi
KEY_B64="$(printf '%s' "$PUBLIC_KEY" | base64 -w0)"

partition_path() {
  local number="$1"
  if [[ "$DISK" =~ [0-9]$ ]]; then
    printf '%sp%s' "$DISK" "$number"
  else
    printf '%s%s' "$DISK" "$number"
  fi
}

ESP="$(partition_path 1)"
SWAP="$(partition_path 2)"
ROOT="$(partition_path 3)"

echo "Target installer: $TARGET"
echo "Target hostname:  $INSTALL_HOSTNAME"
echo "Target disk:      $DISK"
echo
echo "Remote disk inventory:"
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$TARGET" \
  "lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL,SERIAL '$DISK'; test -d /sys/firmware/efi && echo 'Boot mode: UEFI'"
echo
printf 'THIS WILL ERASE %s ON %s. Type exactly "erase %s": ' "$DISK" "$TARGET" "$DISK"
read -r confirmation
if [[ "$confirmation" != "erase $DISK" ]]; then
  echo "Cancelled."
  exit 1
fi

ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=20 "$TARGET" \
  "sudo bash -s -- '$DISK' '$ESP' '$SWAP' '$ROOT' '$INSTALL_HOSTNAME' '$INSTALL_USER' '$STATE_VERSION' '$KEY_B64'" <<'REMOTE_SCRIPT'
set -euo pipefail

disk="$1"
esp="$2"
swap_partition="$3"
root_partition="$4"
install_hostname="$5"
install_user="$6"
state_version="$7"
key_b64="$8"
public_key="$(printf '%s' "$key_b64" | base64 -d)"

if [[ ! -b "$disk" ]]; then
  echo "Target is not a block device: $disk" >&2
  exit 2
fi
if [[ ! -d /sys/firmware/efi ]]; then
  echo "The installer was not booted in UEFI mode." >&2
  exit 2
fi

root_source="$(findmnt -no SOURCE / || true)"
if [[ "$root_source" == "$disk"* ]]; then
  echo "Refusing to erase $disk because the live root is on it." >&2
  exit 2
fi

for command in parted wipefs mkfs.fat mkfs.ext4 mkswap nixos-generate-config nixos-install; do
  command -v "$command" >/dev/null || {
    echo "Missing installer command: $command" >&2
    exit 2
  }
done

umount -R /mnt 2>/dev/null || true
swapoff "$swap_partition" 2>/dev/null || true

# Refuse to continue if anything else from the target disk remains mounted.
if lsblk -nrpo MOUNTPOINT "$disk" | grep -qE '^/'; then
  echo "A target-disk filesystem remains mounted:" >&2
  lsblk -o NAME,PATH,MOUNTPOINTS "$disk" >&2
  exit 2
fi

wipefs --all "$disk"
parted --script "$disk" mklabel gpt
# Match Disko's generated GPT PARTLABEL names so a later switch to the
# repository configuration can reuse this layout without reformatting.
parted --script "$disk" mkpart disk-main-esp fat32 1MiB 513MiB
parted --script "$disk" set 1 esp on
parted --script "$disk" mkpart disk-main-swap linux-swap 513MiB 2561MiB
parted --script "$disk" mkpart disk-main-root ext4 2561MiB 100%
partprobe "$disk"
udevadm settle

mkfs.fat -F 32 -n EFI "$esp"
mkswap -f -L swap "$swap_partition"
mkfs.ext4 -F -L root "$root_partition"

mkdir -p /mnt
mount "$root_partition" /mnt
mkdir -p /mnt/boot
mount "$esp" /mnt/boot
swapon "$swap_partition"

nixos-generate-config --root /mnt

cat > /mnt/etc/nixos/configuration.nix <<EOF
{ ... }:
{
  imports = [ ./hardware-configuration.nix ];

  networking = {
    hostName = "$install_hostname";
    networkmanager.enable = true;
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  users.users."$install_user" = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" ];
    openssh.authorizedKeys.keys = [ "$public_key" ];
  };
  security.sudo.wheelNeedsPassword = false;

  hardware.enableRedistributableFirmware = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "$state_version";
}
EOF

chmod 0600 /mnt/etc/nixos/configuration.nix

echo
echo "Generated installation configuration:"
sed -n '1,220p' /mnt/etc/nixos/configuration.nix
echo
echo "Installing NixOS..."
nixos-install --root /mnt --no-root-password

echo
echo "Installation complete. The machine has NOT been rebooted."
echo "Configuration is stored in /mnt/etc/nixos."
echo "After reviewing it, reboot manually and remove the USB installer."
REMOTE_SCRIPT
