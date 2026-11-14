#!/bin/bash
# Remove n1x-ssam-helper/1.0 and go back to the old surface-n1x-ssam/1.0 (patched in-tree copy).
# By default SSAM is swapped live, without a reboot (--no-reload skips the swap).
# usage: sudo ./rollback.sh [--no-reload]
set -euo pipefail

PKG=n1x-ssam-helper
VER=1.0
OLD=surface-n1x-ssam/1.0
KVER=$(uname -r)
CONF=/etc/modprobe.d/n1x-ssam-helper.conf
RELOAD=1
[ "${1:-}" = "--no-reload" ] && RELOAD=0

[ "$(id -u)" = 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }
[ -f /usr/src/surface-n1x-ssam-1.0/dkms.conf ] ||
	{ echo "/usr/src/surface-n1x-ssam-1.0 is missing; cannot roll back." >&2; exit 1; }

unload_ssam() {
	local m
	if [ -d /sys/module/surface_aggregator ]; then
		for m in $(ls /sys/module/surface_aggregator/holders); do
			echo "   rmmod $m"
			rmmod "$m"
		done
		echo "   rmmod surface_aggregator"
		rmmod surface_aggregator
	fi
	if [ -d /sys/module/n1x_ssam_uartclk ]; then
		echo "   rmmod n1x_ssam_uartclk"
		rmmod n1x_ssam_uartclk
	fi
}

if [ "$RELOAD" = 1 ]; then
	echo "== 1/4 unload the SSAM modules"
	unload_ssam
fi

echo "== 2/4 remove $PKG/$VER and the softdep config"
if dkms status "$PKG/$VER" | grep -q .; then
	dkms remove "$PKG/$VER" --all
fi
rm -f "$CONF"

echo "== 3/4 reinstall $OLD ($KVER)"
dkms install "$OLD" -k "$KVER"
depmod -a "$KVER"
modinfo -k "$KVER" -n surface_aggregator

if [ "$RELOAD" = 0 ]; then
	echo "== 4/4 loading skipped (takes effect at the next boot)"
	exit 0
fi

echo "== 4/4 load the old modules"
modprobe surface_aggregator
modprobe surface_aggregator_registry
udevadm settle || true
modprobe surface_battery
modprobe surface_charger
sleep 2
dmesg | grep -E "N1X UART clock quirk|SAM firmware" | tail -n 4 || true
ls /sys/bus/surface_aggregator/devices/ /sys/class/power_supply/ || true
