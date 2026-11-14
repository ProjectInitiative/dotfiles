#!/bin/bash
# Install and start n1x-thermald and the Tj safety net (an extra ACPI thermal zone). No reboot needed.
#   sudo ./install.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
install -Dm755 "$here/n1x-thermald" /usr/local/bin/n1x-thermald
install -Dm644 "$here/n1x-thermal.aml" /usr/local/lib/n1x-thermal/n1x-thermal.aml
install -m644 "$here/n1x-thermald.service" "$here/n1x-thermal-ssdt.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now n1x-thermal-ssdt.service
echo "== selftest (does scaling_max_freq take effect?)"
/usr/local/bin/n1x-thermald --selftest
systemctl enable --now n1x-thermald.service
sleep 3
systemctl --no-pager --lines=5 status n1x-thermald || true
cat /run/n1x-thermald/status.json 2>/dev/null; echo
