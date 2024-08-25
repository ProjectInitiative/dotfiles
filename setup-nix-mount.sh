#!/usr/bin/env bash
export PATH="$PATH:/usr/sbin:/sbin"                                                       
export NIX_PATH="nixpkgs=channel:nixos-unstable"                                          
sudo mount /dev/mapper/data-root_nixos /mnt                                        
sudo mount /dev/disk/by-partuuid/05399427-3ed0-4da7-bd08-740ddb6ce486 /mnt/boot/
