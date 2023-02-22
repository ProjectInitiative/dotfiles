#!/usr/bin/env bash

mkdir -p ~/.config/containers
cat <<EOF > ~/.config/containers/storage.cfg
[storage]
driver = "overlay"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
EOF

# podman build -t localhost/devbox:latest --format=docker . || exit 1
docker build -t localhost/devbox:latest . || exit 1
IMAGE="localhost/devbox:latest"
# IMAGE="ghcr.io/projectinitiative/devbox:latest"
DISTROBOX_NAME="devbox"

# install distrobox scripts
echo "Installing distrobox"
curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install | sh -s -- --prefix ~/.local

# create devbox
echo "creating distrobox from $IMAGE base image"
distrobox create --image "$IMAGE" --name "$DISTROBOX_NAME" --init
