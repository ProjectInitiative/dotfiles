#!/bin/bash
# Unlink the Caps Lock LED from the key state. Applies at once, no reboot needed.
#   sudo ./install.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
install -m644 "$here/73-surface-capslock-led.rules" /etc/udev/rules.d/
udevadm control --reload
udevadm trigger --action=add --subsystem-match=leds
udevadm settle
for l in /sys/class/leds/input*::capslock; do
	echo "$l: $(grep -o '\[[^]]*\]' $l/trigger)"
done
