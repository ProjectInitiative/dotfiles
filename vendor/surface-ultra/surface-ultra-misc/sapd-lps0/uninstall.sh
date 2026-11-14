#!/bin/bash
# Remove n1x-sapd-lps0.
#   sudo ./uninstall.sh
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
rmmod n1x_sapd_lps0 2>/dev/null
dkms remove n1x-sapd-lps0/1.0 --all
rm -rf /usr/src/n1x-sapd-lps0-1.0
