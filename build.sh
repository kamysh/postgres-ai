#!/usr/bin/env bash
set -e

# Detect platform or use argument
PLATFORM="${1:-$(uname -m)}"

case "$PLATFORM" in
  x86_64|amd64)
    NIX_SYSTEM="x86_64-linux"
    DOCKER_PLATFORM="linux/amd64"
    ;;
  aarch64|arm64)
    NIX_SYSTEM="aarch64-linux"
    DOCKER_PLATFORM="linux/arm64"
    ;;
  *)
    echo "Usage: $0 [x86_64|aarch64]"
    echo "Unsupported platform: $PLATFORM"
    exit 1
    ;;
esac

echo "Building for platform: $NIX_SYSTEM"

# Check if running on macOS or Linux
if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "Building in Docker container (macOS detected)..."
  docker run --rm \
    -v "$(pwd):/build" \
    -w /build \
    --platform "$DOCKER_PLATFORM" \
    nixos/nix:latest \
    sh -c "nix build --extra-experimental-features 'nix-command flakes' .#packages.${NIX_SYSTEM}.dockerImage && \
           cp \$(readlink result) /build/postgres-ai.tar.gz"
else
  echo "Building with Nix..."
  nix build ".#packages.${NIX_SYSTEM}.dockerImage"
  cp "$(readlink result)" postgres-ai.tar.gz
fi

echo "Removing old image if it exists..."
docker rmi postgres-ai:latest 2>/dev/null || true

echo "Loading image into Docker..."
docker load < postgres-ai.tar.gz

echo "Cleaning up..."
rm -f result postgres-ai.tar.gz

echo "Done! Image 'postgres-ai:latest' is ready."
echo "Run: docker-compose up -d"
