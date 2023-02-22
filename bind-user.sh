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

# Bind mount every regular file in each source user's home directory to destination user's home directory
for src_user in "${src_users[@]}"; do
    find "/home/$src_user" -type f -name ".*" -o -not -name ".*" | while read file; do
        # Get the relative path of the file within src_user's home directory
        rel_path=${file#/home/$src_user/}

        # Create the corresponding directory within destination user's home directory and bind mount the file to it
        mkdir -p "$dest_home/$(dirname "$rel_path")"
        sudo mount --bind "$file" "$dest_home/$rel_path"

        # Set the ownership of the mounted file to the destination user
        sudo chown "$dest_user:$dest_user" "$dest_home/$rel_path"
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
}

# Call the undo_mounts function on exit or interrupt
trap "undo_mounts" EXIT INT
