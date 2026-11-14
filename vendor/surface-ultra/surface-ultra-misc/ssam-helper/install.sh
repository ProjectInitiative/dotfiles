#!/bin/bash
# Install n1x-ssam-helper/1.0 and remove the old surface-n1x-ssam/1.0 (patched in-tree copy).
# By default SSAM is swapped live, without a reboot (--no-reload skips the swap).
# usage: sudo ./install.sh [--no-reload]
set -euo pipefail

PKG=n1x-ssam-helper
VER=1.0
OLD=surface-n1x-ssam/1.0
KVER=$(uname -r)
HERE=$(dirname "$(readlink -f "$0")")
SRC=/usr/src/$PKG-$VER
CONF=/etc/modprobe.d/n1x-ssam-helper.conf
RELOAD=1
[ "${1:-}" = "--no-reload" ] && RELOAD=0

[ "$(id -u)" = 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }

echo "== 1/5 source -> $SRC"
rm -rf "$SRC"
install -d "$SRC"
install -m644 "$HERE"/{Kbuild,Makefile,dkms.conf,n1x_ssam_uartclk.c,n1x_ssam_clients.c} "$SRC"/

echo "== 2/5 dkms install $PKG/$VER ($KVER)"
if dkms status "$PKG/$VER" | grep -q .; then
	dkms remove "$PKG/$VER" --all
fi
dkms install "$PKG/$VER" -k "$KVER"

echo "== 3/5 remove the old package $OLD (DKMS puts the stock modules back)"
if dkms status "$OLD" | grep -q .; then
	dkms remove "$OLD" --all
else
	echo "   (not installed)"
fi

echo "== 4/5 modprobe softdep -> $CONF"
install -m644 "$HERE/n1x-ssam-helper.conf" "$CONF"
depmod -a "$KVER"

for m in surface_aggregator surface_aggregator_registry; do
	f=$(modinfo -k "$KVER" -n "$m")
	echo "   $m -> $f"
	case $f in
	*/updates/*) echo "!! $m still resolves to updates/; aborting." >&2; exit 1 ;;
	esac
done

if [ "$RELOAD" = 0 ]; then
	echo "== 5/5 live swap skipped (takes effect at the next boot)"
	exit 0
fi

echo "== 5/5 swapping SSAM without a reboot"
# Unload everything that holds surface_aggregator (battery, charger, registry, ...)
# first, then the aggregator itself. For the old package this only unloads it from memory.
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
unload_ssam
modprobe n1x_ssam_uartclk
modprobe surface_aggregator
modprobe n1x_ssam_clients
udevadm settle || true
modprobe surface_battery
modprobe surface_charger

ok=0
for _ in $(seq 1 20); do
	if [ -e /sys/bus/surface_aggregator/devices/01:02:01:01:00/driver ]; then
		ok=1
		break
	fi
	sleep 0.5
done

echo
dmesg | grep -E "n1x_ssam|SAM UART clock|surface_serial_hub|SAM firmware" | tail -n 8 || true
ls /sys/bus/surface_aggregator/devices/ || true
ls /sys/class/power_supply/ || true

if [ "$ok" = 1 ]; then
	echo "OK: battery/AC work with the stock drivers + helper."
else
	echo "!! no battery device; check dmesg, and if needed: sudo $HERE/rollback.sh" >&2
	exit 1
fi
