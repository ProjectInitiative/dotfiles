#!/usr/bin/env bash
set -euo pipefail

# Configuration
FLAKE_PATH="$(pwd)"  # Default to current directory
FLAKE_TARGET="sd-aarch64.stormjib"
NIX_CACHE_DIR="${HOME}/.cache/nix-sd-direct-builder"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --flake)
      FLAKE_PATH="$2"
      shift 2
      ;;
    --target)
      FLAKE_TARGET="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [--flake PATH] [--target FLAKE_TARGET]"
      echo ""
      echo "Options:"
      echo "  --flake PATH         Path to the flake directory (default: current directory)"
      echo "  --target TARGET      Flake target to build (default: sd-aarch64.stormjib)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "🚀 Direct aarch64 SD image builder"
echo "📂 Flake path: $FLAKE_PATH"
echo "🎯 Target: $FLAKE_TARGET"

# Create cache directory
mkdir -p "$NIX_CACHE_DIR"

# Run the Nix container with appropriate volumes and settings
docker run --rm -it \
  --privileged \
  -v "$FLAKE_PATH":/flake \
  -v "$NIX_CACHE_DIR":/nix \
  -w /flake \
  -e NIX_CONFIG="extra-platforms = aarch64-linux" \
  --entrypoint /bin/sh \
  nixos/nix \
  -c "nix --experimental-features 'nix-command flakes' \
       build '.#$FLAKE_TARGET' \
       --option sandbox false \
       --option extra-platforms aarch64-linux \
       --cores $(nproc) \
       --verbose"

echo "✅ Build complete!"
echo "The result should be in $FLAKE_PATH/result"
