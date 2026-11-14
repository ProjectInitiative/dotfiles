#!/bin/bash
# Remove the hook and unmask the NVIDIA sleep services.
#   sudo ./uninstall.sh
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
rm -f /usr/lib/systemd/system-sleep/surface-ultra-lid-wakeup
systemctl unmask nvidia-suspend.service nvidia-resume.service 2>/dev/null
