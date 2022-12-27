#!/usr/bin/env bash

podman build -t localhost/devbox:latest --format=docker .
IMAGE="localhost/devbox:latest"
# IMAGE="ghcr.io/projectinitiative/devbox:latest"
DISTROBOX_NAME="devbox"

# install distrobox scripts
echo "Installing distrobox"
curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install | sh -s -- --prefix ~/.local

# create devbox
echo "creating distrobox from $IMAGE base image"
distrobox create --image "$IMAGE" --name "$DISTROBOX_NAME" --init
