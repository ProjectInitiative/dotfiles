#!/bin/bash
# Install the upstream (v7.4-rc1) rt721-sdca codec driver with DKMS and switch to it now.
#   sudo ./install.sh
# The sound card is torn down and rebuilt; audio stops for a few seconds. No reboot needed.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
PKG=n1x-rt721-sdca VER=7.4-rc1 SRC=/usr/src/$PKG-$VER
dkms status "$PKG/$VER" | grep -q . && dkms remove "$PKG/$VER" --all
rm -rf "$SRC"; install -d "$SRC"
install -m644 "$here"/{Makefile,Kbuild,dkms.conf,*.c,*.h} "$SRC/"
dkms install "$PKG/$VER"
"$here/reload.sh"
