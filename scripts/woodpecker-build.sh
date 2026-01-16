#!/bin/sh
#
# Smart Wrapper for Woodpecker CI
# Auto-detects build variants (latest/pkg) and runs build.sh for each.
#
# Usage: ./woodpecker-build.sh [IMAGE_NAME]
#
# Env vars required:
#   GITHUB_TOKEN
#   GITHUB_ACTOR (optional)

set -e

IMAGE_NAME="$1"
REGISTRY="${REGISTRY:-ghcr.io}"
BUILD_SCRIPT_URL="https://raw.githubusercontent.com/daemonless/daemonless/main/scripts/build.sh"

if [ -z "$IMAGE_NAME" ]; then
    # Try to detect image name from directory name if not provided
    IMAGE_NAME=$(basename $(pwd))
    echo "Detected image name: $IMAGE_NAME"
fi

FULL_IMAGE="${REGISTRY}/daemonless/${IMAGE_NAME}"

# Fetch build script
mkdir -p scripts
if [ ! -f scripts/build.sh ]; then
    echo "Fetching build script..."
    fetch -qo scripts/build.sh "$BUILD_SCRIPT_URL" || curl -sf -o scripts/build.sh "$BUILD_SCRIPT_URL"
    chmod +x scripts/build.sh
fi

run_build() {
    ./scripts/build.sh \
        --doas \
        --registry "$REGISTRY" \
        --image "$FULL_IMAGE" \
        --skip-wip \
        --login --push \
        "$@"
}

echo "=== Auto-detecting build configurations for $IMAGE_NAME ==="

# Check for Containerfile
if [ -f "Containerfile" ]; then
    if grep -q 'io.daemonless.pkg-source="containerfile"' Containerfile; then
        echo "Detected Package Source (Containerfile)"
        # Build :pkg
        echo ">> Building :pkg"
        run_build \
            --containerfile Containerfile \
            --base-version 15-quarterly \
            --tag pkg \
            --tag-version \
            --version-suffix "-pkg"

        # Build :pkg-latest (aliased to :latest usually?)
        # Wait, if pkg-source="containerfile", usually we want :latest too.
        # The GHA logic builds pkg-latest AND aliases it to latest.
        echo ">> Building :pkg-latest"
        run_build \
            --containerfile Containerfile \
            --base-version 15 \
            --tag pkg-latest \
            --tag-version \
            --version-suffix "-pkg-latest" \
            --alias latest
    else
        echo "Detected Standard Source (Containerfile)"
        # Build :latest
        echo ">> Building :latest"
        run_build \
            --containerfile Containerfile \
            --tag latest \
            --tag-version
    fi
fi

# Check for Containerfile.pkg
if [ -f "Containerfile.pkg" ]; then
    echo "Detected Package Variant (Containerfile.pkg)"
    
    # Build :pkg
    echo ">> Building :pkg"
    run_build \
        --containerfile Containerfile.pkg \
        --base-version 15-quarterly \
        --tag pkg \
        --tag-version \
        --version-suffix "-pkg"

    # Build :pkg-latest
    echo ">> Building :pkg-latest"
    run_build \
        --containerfile Containerfile.pkg \
        --base-version 15 \
        --tag pkg-latest \
        --tag-version \
        --version-suffix "-pkg-latest"
fi

echo "=== All builds complete ==="
