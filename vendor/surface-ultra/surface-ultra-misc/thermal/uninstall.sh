#!/bin/bash
# Remove n1x-thermald and the safety-net service (an ACPI table already loaded stays until the next reboot).
#   sudo ./uninstall.sh
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
systemctl disable --now n1x-thermald.service n1x-thermal-ssdt.service
rm -f /etc/systemd/system/n1x-thermald.service /etc/systemd/system/n1x-thermal-ssdt.service \
	/usr/local/bin/n1x-thermald
rm -rf /usr/local/lib/n1x-thermal
systemctl daemon-reload
