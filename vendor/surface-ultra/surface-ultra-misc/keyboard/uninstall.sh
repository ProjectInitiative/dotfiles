#!/bin/bash
# Remove the rule and link the Caps Lock LED to the key state again.
#   sudo ./uninstall.sh
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
rm -f /etc/udev/rules.d/73-surface-capslock-led.rules
udevadm control --reload
for l in /sys/class/leds/input*::capslock; do
	grep -q 'MSHW0794' $l/device/name 2>/dev/null && echo kbd-capslock > $l/trigger
done
