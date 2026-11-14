#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Install the Surface Laptop Ultra camera support from this checkout: DKMS
# kernel modules, their configuration, and the libcamera / WirePlumber / session
# files that let PipeWire offer both cameras. Safe to re-run (upgrades in place).
#   sudo ./packaging/install.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
TOP=$(cd "$(dirname "$0")/.." && pwd)
PKG=surface-ultra-camera
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$TOP/kernel/dkms.conf")
SRC=/usr/src/$PKG-$VER
FW=/lib/firmware/nvidia/n1x/nvCCU.img

[ -f "$FW" ] || { echo "missing $FW - see firmware/README.md"; exit 1; }
for t in dkms modprobe; do command -v $t >/dev/null || { echo "need $t"; exit 1; }; done
[ -d /usr/share/libcamera/ipa/simple ] || { echo "need libcamera (with its simple IPA)"; exit 1; }

# the 0.1 release fed v4l2loopback from a user-space ISP, sucamd
if [ -e /etc/systemd/system/sucamd.service ]; then
	echo "== removing sucamd (0.1)"
	systemctl disable --now sucamd sucamd-ir 2>/dev/null || true
	rm -f /etc/systemd/system/sucamd.service /etc/systemd/system/sucamd-ir.service /usr/local/bin/sucamd
	systemctl daemon-reload
fi

echo "== DKMS modules ($PKG/$VER)"
for old in $(dkms status "$PKG" 2>/dev/null | sed -n "s#^$PKG/\([^,]*\),.*#\1#p" | sort -u); do
	dkms remove "$PKG/$old" --all || true
	rm -rf "/usr/src/$PKG-$old"
done
rm -rf "$SRC"
install -d "$SRC"
install -m644 "$TOP"/kernel/{dkms.conf,Kbuild,*.c,*.h} "$SRC/"
dkms install "$PKG/$VER"

echo "== configuration"
install -Dm644 "$TOP/packaging/modprobe.conf" /etc/modprobe.d/$PKG.conf
install -Dm644 "$TOP/packaging/modules-load.conf" /etc/modules-load.d/$PKG.conf
install -Dm644 "$TOP/libcamera/configuration.yaml" /usr/share/libcamera/configuration.yaml
install -Dm644 "$TOP/libcamera/ipa/simple/ov02c10.yaml" /usr/share/libcamera/ipa/simple/ov02c10.yaml
install -Dm644 "$TOP/wireplumber/50-surface-ultra-camera.conf" \
	/usr/share/wireplumber/wireplumber.conf.d/50-surface-ultra-camera.conf
install -Dm644 "$TOP/packaging/environment.conf" /usr/lib/environment.d/50-$PKG.conf

echo "== loading the installed drivers (no reboot needed)"
rmmod surface_ultra_cam 2>/dev/null || true
rmmod v4l2loopback 2>/dev/null || true
modprobe surface_ccu_boot
modprobe surface_ultra_cam
echo "done. Log out and back in (or reboot) so that PipeWire runs with the"
echo "new environment; then pick \"Surface Front Camera\" or \"Surface IR Camera\"."
