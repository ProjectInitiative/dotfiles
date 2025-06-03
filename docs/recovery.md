# NixOS System Recovery from an External Environment

This guide outlines the steps to recover or reinstall your NixOS system using an external environment, such as a NixOS live USB or another Linux distribution. It assumes you have access to your NixOS configuration files (e.g., cloned from a Git repository).

## 1. Boot into a Recovery Environment

Boot your machine from a NixOS installation medium (USB stick or DVD) or any other Linux live environment that provides the necessary tools (like `mount`, `chroot`, `git`, and network access).

## 2. Identify and Mount Partitions

You need to identify and mount your NixOS system's partitions.
* **Root partition (`/`)**: Where your NixOS installation resides.
* **EFI System Partition (ESP)** (if applicable, for UEFI systems): Usually mounted at `/boot` or `/efi` within your NixOS system.
* **Other partitions** (if any): Such as `/home`, `/nix`, etc., if they are on separate partitions.

Use tools like `lsblk`, `fdisk -l`, or `gparted` to identify your partitions.

```bash
# List block devices to identify your partitions
lsblk

# Example: Assuming your NixOS root is /dev/sda2 and EFI is /dev/sda1

# Create mount points
sudo mkdir /mnt/nixos
sudo mkdir -p /mnt/nixos/boot # If your EFI partition was mounted at /boot
# or sudo mkdir -p /mnt/nixos/efi # If your EFI partition was mounted at /efi

# Mount the root partition
sudo mount /dev/sdXY /mnt/nixos # Replace /dev/sdXY with your NixOS root partition

# Mount the EFI partition (if applicable)
sudo mount /dev/sdXZ /mnt/nixos/boot # Replace /dev/sdXZ with your EFI partition
# or sudo mount /dev/sdXZ /mnt/nixos/efi

# Mount other partitions if necessary (e.g., /home or a separate /nix)
# sudo mount /dev/sdYA /mnt/nixos/home
# sudo mount /dev/sdYB /mnt/nixos/nix # Only if /nix is on its own partition
```

**Important for LVM**: If your NixOS system uses LVM, you'll need to activate the volume groups first:

```bash
sudo vgscan
sudo vgchange -ay
# Then mount the logical volumes (e.g., /dev/yourVG/rootLV)
```

**Important for Encrypted Partitions**: If your root partition is encrypted (e.g., LUKS), you'll need to unlock it first:

```bash
sudo cryptsetup luksOpen /dev/sdXY nixos_root # Replace /dev/sdXY
# Then mount the decrypted device:
sudo mount /dev/mapper/nixos_root /mnt/nixos
```

## 3. Access Your NixOS Configuration

Ensure your NixOS configuration files (especially `configuration.nix` and `hardware-configuration.nix`) are accessible within the recovery environment. If they are in a Git repository, clone it.

```bash
# Example: Clone your dotfiles/NixOS config repository
git clone <your-git-repo-url> /tmp/myconfigs
```

Your `hardware-configuration.nix` should ideally be the one generated for the target hardware. If you don't have it, you might need to regenerate it or ensure your `configuration.nix` correctly defines file systems and essential hardware.

## 4. Reinstall or Rebuild NixOS

You have two main approaches: `nixos-install` for a fresh-like install (useful if the system is heavily corrupted) or `nixos-rebuild` within a chroot (useful for fixing configurations or updating).

### Option A: Using `nixos-install` (Recommended for severe issues or re-installation)

This command will reinstall NixOS to the mounted partitions using your specified configuration. It typically handles bootloader installation as well.

Ensure `hardware-configuration.nix` is in place.

If you cloned your configs to `/tmp/myconfigs`, and your main configuration is `/tmp/myconfigs/nixos/configuration.nix`, make sure `/tmp/myconfigs/nixos/hardware-configuration.nix` exists and is correct. If you need to generate it for the target system:

```bash
sudo nixos-generate-config --root /mnt/nixos --dir /tmp/myconfigs/nixos
# Review the generated /tmp/myconfigs/nixos/hardware-configuration.nix
```

Run `nixos-install`: Point to your `configuration.nix`.

```bash
sudo nixos-install --root /mnt/nixos -I nixos-config=/tmp/myconfigs/nixos/configuration.nix
```

If your configuration is structured differently (e.g., using flakes), adjust the command accordingly. For flakes:

```bash
# Ensure your flake.nix and configuration are in /tmp/myconfigs
sudo nixos-install --root /mnt/nixos --flake /tmp/myconfigs#yourHostName
```

This command will build the system based on your configuration and install it to `/mnt/nixos`. It will also attempt to install the bootloader.

### Option B: Using `chroot` and `nixos-rebuild` (For configuration fixes)

This method is more like rebuilding a running system, but from the outside.

Prepare and enter the chroot environment:
Note: Some recovery environments might provide `nixos-enter` which simplifies this.

```bash
# If nixos-enter is available in your live environment:
sudo nixos-enter --root /mnt/nixos
```

If `nixos-enter` is not available, you can perform the steps manually:

```bash
sudo mount --rbind /dev /mnt/nixos/dev
sudo mount --rbind /proc /mnt/nixos/proc
sudo mount --rbind /sys /mnt/nixos/sys
sudo chroot /mnt/nixos /nix/var/nix/profiles/system/sw/bin/bash
```

Inside the chroot:
Navigate to your configuration directory. You may need to clone your git repo again inside the chroot if networking is available.

```bash
# Inside chroot
source /etc/profile # Load environment variables
# Assuming your configs are now at /path/to/your/configs inside the chroot
cd /path/to/your/configs

# Rebuild the system
nixos-rebuild switch --config ./nixos/configuration.nix 
# Or for flakes:
# nixos-rebuild switch --flake .#yourHostName
```

This will rebuild the system and update the bootloader if configured.

## 5. Unmount and Reboot

After the installation or rebuild is complete:

Exit chroot (if you used it):

```bash
exit
```

Unmount all partitions in reverse order of mounting:

```bash
sudo umount -R /mnt/nixos
# If you used cryptsetup:
# sudo cryptsetup luksClose nixos_root 
```

Reboot your system:

```bash
sudo reboot
```

Remove the live USB/medium and your system should boot into the recovered NixOS installation.

## Troubleshooting Tips:

* **Bootloader Issues**: If the system doesn't boot, you might need to manually reinstall the bootloader.
    * For GRUB: `grub-install --target=x88_64-efi --efi-directory=/boot --bootloader-id=NixOS` (adjust paths as needed).
    * For systemd-boot: `bootctl --path=/boot install`.
    * These commands are typically run from within the chroot environment or by `nixos-install`.
* **Network Access**: Ensure you have network access in the recovery environment if you need to clone repositories or download Nix packages.
* **`hardware-configuration.nix`**: A mismatched or missing `hardware-configuration.nix` is a common source of problems. Regenerating it on the target hardware (`nixos-generate-config --root /mnt/nixos`) is often a good idea if you suspect issues.
