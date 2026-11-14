#!/bin/bash
# Install n1x-sapd-lps0 with DKMS and load it. No reboot needed.
#   sudo ./install.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
PKG=n1x-sapd-lps0 VER=1.0 SRC=/usr/src/n1x-sapd-lps0-1.0
dkms status "$PKG/$VER" | grep -q . && dkms remove "$PKG/$VER" --all
rm -rf "$SRC"; install -d "$SRC"
install -m644 "$here"/{Makefile,Kbuild,dkms.conf,n1x_sapd_lps0.c} "$SRC/"
dkms install "$PKG/$VER"
rmmod n1x_sapd_lps0 2>/dev/null || true
modprobe n1x_sapd_lps0
sleep 0.5
journalctl -k -b --no-pager | grep -i "MSHW0299" | tail -2
f=/sys/bus/platform/devices/MSHW0299:00/stats
[ -r "$f" ] && { cat "$f"; echo "OK: bound to MSHW0299"; } || { echo "!! not bound; see journalctl -k"; exit 1; }
