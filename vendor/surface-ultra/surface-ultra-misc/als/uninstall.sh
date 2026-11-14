#!/bin/bash
# Remove n1x-spi-hid.
#   sudo ./uninstall.sh
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
rmmod hid_sensor_als hid_sensor_custom 2>/dev/null
rmmod n1x_spi_hid 2>/dev/null
dkms remove n1x-spi-hid/1.0 --all
rm -rf /usr/src/n1x-spi-hid-1.0
