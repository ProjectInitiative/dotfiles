
# boot.cmd

# Set the device and partition to boot from
setenv devtype mmc
setenv devnum 0
setenv partition 1

# Load the extlinux.conf file
if load ${devtype} ${devnum}:${partition} ${loadaddr} /extlinux/extlinux.conf; then
    # Source the extlinux.conf file to get the boot entries
    env import -t ${loadaddr} ${filesize}
    # Run the default boot entry
    run bootcmd
else
    echo "Could not load extlinux.conf"
fi
