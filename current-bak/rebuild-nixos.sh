#!/usr/bin/env bash
export PATH="$PATH:/usr/sbin:/sbin"
export NIX_PATH="nixpkgs=channel:nixos-unstable"
sudo sysctl -w fs.file-max=1000000000
sudo PATH="$PATH" NIX_PATH="$NIX_PATH" `which nixos-install` --root /mnt
