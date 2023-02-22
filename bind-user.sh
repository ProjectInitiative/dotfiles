#!/bin/bash

# List of source users to mount
src_users=(installer linuxbrew)

# Destination user
dest_user=$(whoami)
dest_home="/home/$dest_user"

# Check if destination user has permission to access source users' home directories
# for src_user in "${src_users[@]}"; do
#     if [ ! -r "/home/$src_user" ]; then
#         echo "Error: $dest_user does not have read permission for /home/$src_user"
#         exit 1
#     fi
# done

# Enable the dotglob option to include hidden files
shopt -s dotglob

# Bind mount every regular file in each source user's home directory to destination user's home directory
for src_user in "${src_users[@]}"; do
    # Iterate over every subdirectory in the source user's home directory
    for subdir in /home/${src_user}/*; do
      # Check if the subdir is a directory
      if [ -d "$subdir" ]; then
        # Get the name of the subdirectory
        subdir_name=$(basename $subdir)
    
        # Create the corresponding directory in the destination user's home directory
        mkdir -p /home/${dest_user}/${subdir_name}
    
        # Bind mount the source subdirectory to the destination subdirectory
        mount --bind $subdir /home/${dest_user}/${subdir_name}
    
        # Make sure the mount persists across reboots
        echo "$subdir /home/${dest_user}/${subdir_name} none bind 0 0" >> /etc/fstab
      fi
    done
done

# Function to undo the mounts
undo_mounts() {
    # Unmount every path in destination user's home directory that is a bind mount
    grep -w "$dest_home" /proc/mounts | while read line; do
        mount_point=$(echo "$line" | awk '{print $2}')
        if grep -q "^$mount_point " /proc/self/mountinfo; then
            sudo umount "$mount_point"
        fi
    done
    
    # Disable the dotglob option to avoid unintended consequences
    shopt -u dotglob
}

# Call the undo_mounts function on exit or interrupt
trap "undo_mounts" EXIT INT

# Disable the dotglob option to avoid unintended consequences
shopt -u dotglob