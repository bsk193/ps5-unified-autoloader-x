#!/usr/bin/env bash
# ps5-unified-autoloader-x — Versioned Build Script
#
# Fork note: the embedded fallback manager is Payload Manager X
# (bsk193/ps5-payload-manager-x), not the official pldmgr. It is staged to the
# local filename pldmgr.elf so the Makefile's xxd symbol names (pldmgr_elf /
# pldmgr_elf_len, referenced by src/main.c) stay unchanged.
#
# Usage:
#   ./build_release.sh              # download pre-built pldmgrx ELF (default)
#   ./build_release.sh -d           # same as above
#   ./build_release.sh --download-deps
#   ./build_release.sh -b           # build pldmgrx from source (uses its own Docker)
#   ./build_release.sh --build-deps
#
# PLDMGRX_PORT selects the Payload Manager X HTTP port for -b builds:
#   8084 (default) -> drop-in replacement for the official manager
#   8184           -> runs alongside the official manager
set -e
cd "$(dirname "$0")"

PLDMGRX_PORT="${PLDMGRX_PORT:-8084}"

# -----------------------------------------------------------------------
# Parse flags
# -----------------------------------------------------------------------
DEP_ACTION="download"  # default

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --build-deps|-b)    DEP_ACTION="build" ;;
        --download-deps|-d) DEP_ACTION="download" ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# -----------------------------------------------------------------------
# Extract version from include/autoloader.h
# -----------------------------------------------------------------------
VERSION=$(grep '#define AUTOLOADER_VERSION' include/autoloader.h \
    | awk '{print $3}' | tr -d '"' | tr -d '\r')

if [ -z "$VERSION" ]; then
    echo "Error: Could not find AUTOLOADER_VERSION in include/autoloader.h"
    exit 1
fi

# -----------------------------------------------------------------------
# Compute short commit hash (or DEV_<timestamp> if working tree is dirty)
# -----------------------------------------------------------------------
if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
    SHORT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
else
    SHORT_HASH="DEV_$(date -u +"%Y%m%d_%H%M%S")"
fi

OUTPUT_ELF="autoloader_v${VERSION}_${SHORT_HASH}.elf"
IMAGE_NAME="ps5-unified-autoloader-x-sdk"

echo "=== ps5-unified-autoloader-x v${VERSION} (${SHORT_HASH}) ==="

# -----------------------------------------------------------------------
# Step 1: Obtain pldmgr.elf
# -----------------------------------------------------------------------
if [ "$DEP_ACTION" = "build" ]; then
    echo "[1/3] Building Payload Manager X from source (port ${PLDMGRX_PORT})..."

    if [ ! -e "third_party/ps5-payload-manager-x/.git" ]; then
        echo "      Error: ps5-payload-manager-x submodule not initialised."
        echo "      Run: git submodule update --init --recursive"
        exit 1
    fi

    # Payload Manager X's own build_release.sh produces a plain (non-X) pldmgr
    # build, so replicate what its release workflow does instead: build the
    # React frontend on the host, then `make ... PLDMGRX=1 PLDMGRX_PORT=<port>`
    # inside its own SDK image (it needs libmicrohttpd / mbedTLS / libcurl).
    PLDMGRX_IMAGE="ps5-payload-sdk-pldmgr"

    (
        cd third_party/ps5-payload-manager-x

        echo "      Building React frontend..."
        make frontend-build

        if [[ "$(docker images -q "$PLDMGRX_IMAGE" 2>/dev/null)" == "" ]]; then
            echo "      Docker image ${PLDMGRX_IMAGE} not found. Building..."
            docker build -t "$PLDMGRX_IMAGE" -f Dockerfile.sdk .
        fi

        echo "      Building native ELF via Docker..."
        docker run --rm -v "$(pwd)":/src -w /src "$PLDMGRX_IMAGE" \
            make clean all PLDMGRX=1 "PLDMGRX_PORT=${PLDMGRX_PORT}"
    )

    PLDMGR_ELF="third_party/ps5-payload-manager-x/pldmgrx_${PLDMGRX_PORT}.elf"
    if [ ! -f "$PLDMGR_ELF" ]; then
        echo "      Error: build succeeded but $PLDMGR_ELF was not produced."
        exit 1
    fi

    cp "$PLDMGR_ELF" pldmgr.elf
    echo "      pldmgr.elf obtained from source build: $(basename "$PLDMGR_ELF")"

else
    echo "[1/3] Downloading pre-built Payload Manager X ELF from GitHub releases..."

    PLDMGR_URL=$(curl -s https://api.github.com/repos/bsk193/ps5-payload-manager-x/releases/latest \
        | grep "browser_download_url" \
        | grep 'pldmgrx_v.*\.elf"' \
        | head -n 1 \
        | sed 's/.*"browser_download_url": "\(.*\)".*/\1/')

    if [ -z "$PLDMGR_URL" ]; then
        echo "      Error: Could not find a pldmgrx release URL."
        echo "      Try running with -b to build from source instead."
        exit 1
    fi

    echo "      Downloading: $PLDMGR_URL"
    curl -L -o pldmgr.elf "$PLDMGR_URL"
    echo "      pldmgr.elf downloaded (Payload Manager X)."
fi

# -----------------------------------------------------------------------
# Step 2: Build / verify the Docker image
# -----------------------------------------------------------------------
echo "[2/3] Checking Docker image (${IMAGE_NAME})..."

if [[ "$(docker images -q "$IMAGE_NAME" 2>/dev/null)" == "" ]]; then
    echo "      Image not found. Building (this may take a few minutes)..."
    docker build -t "$IMAGE_NAME" -f Dockerfile.sdk .
    echo "      Docker image built."
else
    echo "      Docker image already present."
fi

# -----------------------------------------------------------------------
# Step 3: Build autoloader.elf inside Docker
# -----------------------------------------------------------------------
echo "[3/3] Building autoloader.elf via Docker..."
docker run --rm -v "$(pwd)":/src -w /src "$IMAGE_NAME" make clean all

# -----------------------------------------------------------------------
# Rename to versioned output
# -----------------------------------------------------------------------
if [ ! -f "autoloader.elf" ]; then
    echo "Error: autoloader.elf not found after build."
    exit 1
fi

mv autoloader.elf "$OUTPUT_ELF"
echo ""
echo "=== Build complete! ==="
echo "    Output: $OUTPUT_ELF"
