#!/bin/bash
# Install n1x-spi-hid (HID over SPI for the Surface Laptop Ultra sensor hub) with DKMS and
# load it. No reboot needed.
#   sudo ./install.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
PKG=n1x-spi-hid VER=1.0 SRC=/usr/src/n1x-spi-hid-1.0
dkms status "$PKG/$VER" | grep -q . && dkms remove "$PKG/$VER" --all
rm -rf "$SRC"; install -d "$SRC"
install -m644 "$here"/{Makefile,dkms.conf,spi-hid-acpi.c,spi-hid-core.c,spi-hid-core.h,spi-hid-trace.h,spi-hid.h} "$SRC/"
dkms install "$PKG/$VER"
# hand-loaded test builds, and the stock core they used
rmmod n1x_spi_hid spi_hid_acpi 2>/dev/null || true
rmmod spi_hid 2>/dev/null || true
modprobe n1x-spi-hid
for _ in $(seq 20); do
	for d in /sys/bus/iio/devices/iio:device*; do
		[ "$(cat $d/name 2>/dev/null)" = als ] && { echo "OK: $d (als), $(cat $d/in_illuminance_raw) raw"; exit 0; }
	done
	sleep 0.5
done
echo "!! the als device did not appear; see journalctl -k"
exit 1
