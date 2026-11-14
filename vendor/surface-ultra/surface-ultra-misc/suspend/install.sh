#!/bin/bash
# Lid-closed suspend: stop the keyboard, touchpad and power button from waking the machine.
# Optionally (--mask-nvidia-sleep) mask nvidia-suspend/resume.service so keys work right after resume.
# Applies from the next suspend, no reboot needed.
#   sudo ./install.sh [--mask-nvidia-sleep]
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
install -m755 "$here/surface-ultra-lid-wakeup" /usr/lib/systemd/system-sleep/
echo "installed /usr/lib/systemd/system-sleep/surface-ultra-lid-wakeup"
if [ "${1:-}" = --mask-nvidia-sleep ]; then
	p=/proc/driver/nvidia/params
	if ! grep -qs '^UseKernelSuspendNotifiers: 1' $p || ! grep -qs '^PreserveVideoMemoryAllocations: 1' $p; then
		echo "NVreg_UseKernelSuspendNotifiers=1 and NVreg_PreserveVideoMemoryAllocations=1 are needed first; not masking"
		exit 1
	fi
	systemctl mask nvidia-suspend.service nvidia-resume.service
fi
