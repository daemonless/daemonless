#!/bin/sh
#
# Shared build script for daemonless base image
# Works with both GitHub Actions (via vmactions) and Woodpecker CI
#
# Version: 1.0.0
#
# Usage: ./scripts/build-base.sh [OPTIONS]
#   --registry REGISTRY       Container registry (default: ghcr.io)
#   --image IMAGE             Full image name (e.g., ghcr.io/daemonless/base)
#   --freebsd-version VER     FreeBSD major version (14 or 15)
#   --pkg-branch BRANCH       Package branch: latest or quarterly
#   --push-latest             Also push :latest tag (only for primary build)
#   --push                    Push to registry
#   --login                   Login to registry (requires GITHUB_TOKEN env var)
#   --doas                    Use doas for podman commands
#
set -e

BUILD_SCRIPT_VERSION="1.0.0"

# Defaults
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-}"
FREEBSD_VERSION="15"
PKG_BRANCH="latest"
PUSH_LATEST="false"
DO_PUSH="false"
DO_LOGIN="false"
PODMAN="podman"

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --image)
            IMAGE_NAME="$2"
            shift 2
            ;;
        --freebsd-version)
            FREEBSD_VERSION="$2"
            shift 2
            ;;
        --pkg-branch)
            PKG_BRANCH="$2"
            shift 2
            ;;
        --push-latest)
            PUSH_LATEST="true"
            shift
            ;;
        --push)
            DO_PUSH="true"
            shift
            ;;
        --login)
            DO_LOGIN="true"
            shift
            ;;
        --doas)
            PODMAN="doas podman"
            shift
            ;;
        --version)
            echo "build-base.sh version $BUILD_SCRIPT_VERSION"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required args
if [ -z "$IMAGE_NAME" ]; then
    echo "Error: --image is required"
    exit 1
fi

# Build directory
BUILD_DIR="${FREEBSD_VERSION}"
if [ ! -d "$BUILD_DIR" ]; then
    echo "Error: Build directory not found: $BUILD_DIR"
    exit 1
fi

# Determine tags
if [ "$PKG_BRANCH" = "quarterly" ]; then
    PRIMARY_TAG="${FREEBSD_VERSION}-quarterly"
else
    PRIMARY_TAG="${FREEBSD_VERSION}"
fi

echo "=== Build Configuration ==="
echo "Script Version:  $BUILD_SCRIPT_VERSION"
echo "Registry:        $REGISTRY"
echo "Image:           $IMAGE_NAME"
echo "FreeBSD Version: $FREEBSD_VERSION"
echo "PKG Branch:      $PKG_BRANCH"
echo "Primary Tag:     $PRIMARY_TAG"
echo "Push Latest:     $PUSH_LATEST"
echo "Push:            $DO_PUSH"
echo "Podman:          $PODMAN"
echo ""

# Login to registry
if [ "$DO_LOGIN" = "true" ]; then
    if [ -z "$GITHUB_TOKEN" ]; then
        echo "Error: GITHUB_TOKEN required for --login"
        exit 1
    fi
    echo "=== Logging in to Registry ==="
    echo "$GITHUB_TOKEN" | $PODMAN login "$REGISTRY" -u "${GITHUB_ACTOR:-daemonless}" --password-stdin
fi

# Build image
echo "=== Building Image ==="
cd "$BUILD_DIR"
$PODMAN build --network=host \
    --build-arg PKG_BRANCH="$PKG_BRANCH" \
    -t "${IMAGE_NAME}:build" .

# Extract FreeBSD version
echo "=== Extracting Version ==="
VERSION=$($PODMAN run --rm --entrypoint="" "${IMAGE_NAME}:build" freebsd-version | tr -d '\n')
echo "FreeBSD Version: $VERSION"

# Show image info
echo "=== Image Info ==="
$PODMAN images | grep -E "(REPOSITORY|${IMAGE_NAME})" || true

# Push if requested
if [ "$DO_PUSH" = "true" ]; then
    # Push primary tag (e.g., :15 or :15-quarterly)
    echo "=== Tagging and Pushing :${PRIMARY_TAG} ==="
    $PODMAN tag "${IMAGE_NAME}:build" "${IMAGE_NAME}:${PRIMARY_TAG}"
    $PODMAN push "${IMAGE_NAME}:${PRIMARY_TAG}"

    # Push full version tag (e.g., :15.0-RELEASE-p1) - only for latest branch
    if [ "$PKG_BRANCH" = "latest" ] && [ -n "$VERSION" ]; then
        echo "=== Tagging and Pushing :${VERSION} ==="
        $PODMAN tag "${IMAGE_NAME}:build" "${IMAGE_NAME}:${VERSION}"
        $PODMAN push "${IMAGE_NAME}:${VERSION}"
    fi

    # Push :latest if requested
    if [ "$PUSH_LATEST" = "true" ]; then
        echo "=== Pushing :latest ==="
        $PODMAN tag "${IMAGE_NAME}:build" "${IMAGE_NAME}:latest"
        $PODMAN push "${IMAGE_NAME}:latest"
    fi

    echo "=== Push Complete ==="
else
    echo "=== Skipping push (use --push to push) ==="
fi
