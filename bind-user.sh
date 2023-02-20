#!/bin/env bash

# Set the source user name
src_user="installer"

# Get the current user name
dest_user=$(whoami)

sudo chown -R ${dest_user}:${dest_user} /home/${src_user}
# Check if the destination user has permission to access the source user's home directory
if [ ! -r /home/${src_user} -o ! -x /home/${src_user} ]; then
  # If the destination user does not have the required permissions, grant them
  sudo chmod +rx /home/${src_user}
  if [ $? -ne 0 ]; then
    echo "Error: failed to grant ${dest_user} permission to access /home/${src_user}"
    exit 1
  fi
fi

# Enable the dotglob option to include hidden files
shopt -s dotglob

# Iterate over every subdirectory in the source user's home directory
for subdir in /home/${src_user}/*; do
  # Get the name of the subdirectory
  subdir_name=$(basename $subdir)

  if [ -d "$subdir" ]; then

	  # Create the corresponding directory in the destination user's home directory
	  mkdir -p /home/${dest_user}/${subdir_name}

  fi

  # Bind mount the source subdirectory to the destination subdirectory
  sudo mount -o bind $subdir /home/${dest_user}/${subdir_name}
  
  # Make sure the mount persists across reboots
	# echo "$subdir /home/${dest_user}/${subdir_name} none bind 0 0" | sudo tee /etc/fstab
done

# Disable the dotglob option to avoid unintended consequences
shopt -u dotglob
