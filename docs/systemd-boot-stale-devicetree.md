# systemd-boot Fails on Stale Device Tree After Kernel Switch

## Issue

`nixos-rebuild switch` fails on the **remote host** with:

```
FileNotFoundError: [Errno 2] No such file or directory: '/nix/store/<hash>-linux-<version>/dtbs/rockchip/<board>.dtb'
Failed to install bootloader
```

The source dtb path in the error does not match the current generation's kernel — it references an **old, GC'd kernel**.

## Root Cause

There are two factors that combine to cause this:

### 1. systemd-boot builder doesn't guard missing source files

The `copy_if_not_exists()` function in `systemd-boot-builder.py` only checks if the **destination** (on the ESP) exists:

```python
def copy_if_not_exists(source: Path, dest: Path) -> None:
    if not dest.exists():          # ← checks destination only
        shutil.copyfile(source, tmppath)   # ← crashes if source was GC'd
```

It doesn't verify the **source** file exists before attempting the copy.

### 2. Bootloader iterates all generations

When generating/updating boot entries, the builder scans **every generation** in the system profile (`/nix/var/nix/profiles/system`). If an old generation's `boot.json` references a device tree from a kernel that has since been garbage-collected, the builder crashes trying to copy the missing dtb file to the ESP.

This is most likely to happen when you switch the kernel package used by a host (e.g., from native `linuxPackagesRK3588` to cross-compiled `linuxPackagesCross`), because:
- Old boot entries still reference the previous kernel's store path
- `nix-collect-garbage` removes the old kernel
- The next `nixos-rebuild switch` fails because the old dtb source is gone

## Fix

Delete old system generations on the **target host** so the bootloader doesn't try to process their boot entries:

```bash
# On the target host:
sudo nix-env --delete-generations old -p /nix/var/nix/profiles/system
sudo nix-collect-garbage
```

Then re-run `nixos-rebuild switch` — only the current (correct) generation will be processed.

## Prevention

Before switching kernel packages on a host, always clean old generations first:

```bash
nixos-rebuild switch --target-host <host> --flake .#<host>  # deploy the new kernel
ssh <host> sudo nix-env --delete-generations old -p /nix/var/nix/profiles/system
ssh <host> sudo nix-collect-garbage
```
