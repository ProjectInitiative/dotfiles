FROM nixos/nix:latest

# Enable flakes
RUN mkdir -p /etc/nix && \
    echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf

# Create user properly
# RUN useradd -m -u 1000 -s /bin/bash kylepzak

# Set working directory
WORKDIR /config

# Copy flake for build step (will be mounted at runtime)
COPY . .

# Build home-manager configuration
RUN nix run github:nix-community/home-manager/master -- build --flake .#"root@docker"
RUN nix-env -e man-db-2.13.0
RUN nix run github:nix-community/home-manager/master -- switch --flake .#"root@docker"

# Set the default command
CMD ["/bin/bash"]
