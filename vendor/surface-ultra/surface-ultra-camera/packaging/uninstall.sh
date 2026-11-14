#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Remove everything install.sh put in place (the firmware in /lib/firmware is left alone).
#   sudo ./packaging/uninstall.sh
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
PKG=surface-ultra-camera

# sucamd: the 0.1 release
systemctl disable --now sucamd sucamd-ir 2>/dev/null
rm -f /etc/systemd/system/sucamd.service /etc/systemd/system/sucamd-ir.service /usr/local/bin/sucamd
systemctl daemon-reload
rmmod surface_ultra_cam surface_ccu_boot 2>/dev/null
for v in $(dkms status "$PKG" 2>/dev/null | sed -n "s#^$PKG/\([^,]*\),.*#\1#p" | sort -u); do
	dkms remove "$PKG/$v" --all
	rm -rf "/usr/src/$PKG-$v"
done
rm -f /etc/modprobe.d/$PKG.conf /etc/modules-load.d/$PKG.conf \
	/usr/share/libcamera/configuration.yaml /usr/share/libcamera/ipa/simple/ov02c10.yaml \
	/usr/share/wireplumber/wireplumber.conf.d/50-surface-ultra-camera.conf \
	/usr/lib/environment.d/50-$PKG.conf
echo "removed"
