#!/bin/bash
# Keep the USB4 tunnel root ports awake. Applies at once, no reboot needed.
#   sudo ./install.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
install -m644 "$here/75-n1x-usb4-tunnel-pm.rules" /etc/udev/rules.d/
udevadm control --reload
udevadm trigger --action=add --subsystem-match=pci --attr-match=vendor=0x10de --attr-match=device=0x22cf
udevadm settle
for d in /sys/bus/pci/devices/*; do
	[ "$(cat $d/vendor)" = 0x10de ] && [ "$(cat $d/device)" = 0x22cf ] || continue
	echo "$(basename $d): control=$(cat $d/power/control) runtime=$(cat $d/power/runtime_status)"
done
