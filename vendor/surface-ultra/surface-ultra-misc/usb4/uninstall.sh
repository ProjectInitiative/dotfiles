#!/bin/bash
# Remove the rule and let the ports runtime-suspend again.
#   sudo ./uninstall.sh
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
rm -f /etc/udev/rules.d/75-n1x-usb4-tunnel-pm.rules
udevadm control --reload
for d in /sys/bus/pci/devices/*; do
	[ "$(cat $d/vendor)" = 0x10de ] && [ "$(cat $d/device)" = 0x22cf ] && echo auto > $d/power/control
done
