#!/bin/bash

# List of source users to mount
src_users=(linuxbrew installer)

# Destination user
dest_user=$(whoami)
dest_home="/home/$dest_user"
dest_upper_layer="$dest_home/.dotfiles.overlay"
dest_work_layer="$dest_home/.dotfiles.work"

dest_lower_layer="$dest_home"
for src_user in "${src_users[@]}"; do

    dest_lower_layer="$dest_lower_layer:/home/$src_user"
    sudo chown -R ${dest_user}:${dest_user} "/home/$src_user"

done

mkdir -p "$dest_upper_layer"
mkdir -p "$dest_work_layer"

sudo mount -t overlay overlay -o "lowerdir=$dest_lower_layer,upperdir=$dest_upper_layer,workdir=$dest_work_layer" $dest_home

