#!/bin/bash
# Remove the DKMS rt721-sdca and go back to the kernel's own module.
#   sudo ./uninstall.sh
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
dkms remove n1x-rt721-sdca/7.4-rc1 --all
rm -rf /usr/src/n1x-rt721-sdca-7.4-rc1
depmod -a
"$here/reload.sh"
