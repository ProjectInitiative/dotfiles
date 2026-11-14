#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Extract the NVIDIA N1X camera CCU firmware (nvCCU.img) from your own Windows install.
#
# The firmware is NVIDIA's property and is not redistributed here; every owner extracts it
# from the Windows partition that shipped on their own machine. This reads the Windows NTFS
# partition read-only, finds the newest nvCCU driver package and copies nvCCU.img next to
# this script. Install it with:
#   sudo install -Dm644 nvCCU.img /lib/firmware/nvidia/n1x/nvCCU.img
#
# usage:
#   sudo ./extract-from-windows.sh                 # auto-detect the Windows partition
#   sudo ./extract-from-windows.sh /dev/nvme0n1p3  # or name it explicitly
#   ./extract-from-windows.sh /mnt/win             # or point at an already-mounted Windows root
set -eu

here=$(cd "$(dirname "$0")" && pwd)

say() { printf '%s\n' "$*" >&2; }
die() { say "error: $*"; exit 1; }

# ---- locate a Windows root ($win) ----
mnt=""          # set if we mounted it ourselves and must unmount
win=""
arg=${1:-}

find_in_root() {
	# echo the DriverStore dir if this looks like a Windows root
	[ -d "$1/Windows/System32/DriverStore/FileRepository" ] &&
		echo "$1/Windows/System32/DriverStore/FileRepository"
}

if [ -n "$arg" ] && [ -d "$arg" ]; then
	win="$arg"
elif [ -n "$arg" ] && [ -b "$arg" ]; then
	[ "$(id -u)" = 0 ] || die "mounting $arg needs root; re-run with sudo"
	mnt=$(mktemp -d)
	mount -t ntfs3 -o ro "$arg" "$mnt" || mount -t ntfs -o ro "$arg" "$mnt" ||
		die "could not mount $arg read-only"
	win="$mnt"
else
	# already mounted somewhere?
	for m in /mnt/win /mnt/windows /run/media/*/* /media/*/*; do
		[ -d "$m" ] && find_in_root "$m" >/dev/null 2>&1 && { win="$m"; break; }
	done
	# otherwise try to auto-mount an NTFS partition that contains /Windows
	if [ -z "$win" ]; then
		[ "$(id -u)" = 0 ] || die "no mounted Windows found; re-run with sudo, or pass the partition (e.g. /dev/nvme0n1p3) or a mount point"
		for dev in $(lsblk -prno NAME,FSTYPE | awk '$2 ~ /ntfs/ {print $1}'); do
			mnt=$(mktemp -d)
			if mount -t ntfs3 -o ro "$dev" "$mnt" 2>/dev/null || mount -t ntfs -o ro "$dev" "$mnt" 2>/dev/null; then
				if find_in_root "$mnt" >/dev/null 2>&1; then win="$mnt"; say "found Windows on $dev"; break; fi
				umount "$mnt"; rmdir "$mnt"; mnt=""
			else
				rmdir "$mnt"; mnt=""
			fi
		done
	fi
fi
[ -n "$win" ] || die "could not find a Windows partition with a DriverStore"

cleanup() { [ -n "$mnt" ] && { umount "$mnt" 2>/dev/null || true; rmdir "$mnt" 2>/dev/null || true; }; }
trap cleanup EXIT

repo=$(find_in_root "$win") || die "$win is not a Windows root"

# ---- pick the newest nvccu package (by DriverVer date in the .inf) ----
best=""; best_key=""
for d in "$repo"/nvccu.inf_arm64_*/; do
	[ -f "$d/nvCCU.img" ] || continue
	ver=$(grep -ai '^DriverVer' "$d/nvCCU.inf" 2>/dev/null | head -1)
	# DriverVer = MM/DD/YYYY,a.b.c.d  -> sort key YYYYMMDD
	key=$(printf '%s' "$ver" | sed -nE 's#.*= *([0-9]{2})/([0-9]{2})/([0-9]{4}).*#\3\1\2#p')
	[ -n "$key" ] || key=$(stat -c %Y "$d/nvCCU.img")
	if [ -z "$best_key" ] || [ "$key" -gt "$best_key" ] 2>/dev/null; then
		best="$d"; best_key="$key"
	fi
done
[ -n "$best" ] || die "no nvccu.inf_arm64_*/nvCCU.img under $repo"

say "using: $best"
grep -ai '^DriverVer' "$best/nvCCU.inf" 2>/dev/null | head -1 | sed 's/^/  /' >&2
cp -f "$best/nvCCU.img" "$here/nvCCU.img"
say "copied -> $here/nvCCU.img"

say "done. To use it: sudo install -Dm644 '$here/nvCCU.img' /lib/firmware/nvidia/n1x/nvCCU.img"
