#!/bin/sh
#
# Shared build script for daemonless intermediate base images (arr-base, nginx-base)
# Works with both GitHub Actions (via vmactions) and Woodpecker CI
#
# Version: 1.0.0
#
# Usage: ./scripts/build-intermediate.sh [OPTIONS]
#   --registry REGISTRY       Container registry (default: ghcr.io)
#   --image IMAGE             Full image name (e.g., ghcr.io/daemonless/arr-base)
#   --base-version VERSION    Base image version arg (15 or 15-quarterly)
#   --tags TAG1,TAG2,...      Comma-separated tags to push
#   --push                    Push to registry
#   --login                   Login to registry (requires GITHUB_TOKEN env var)
#   --doas                    Use doas for podman commands
#
set -e

BUILD_SCRIPT_VERSION="1.0.0"

# Defaults
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-}"
BASE_VERSION="15"
TAGS=""
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
        --base-version)
            BASE_VERSION="$2"
            shift 2
            ;;
        --tags)
            TAGS="$2"
            shift 2
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
            echo "build-intermediate.sh version $BUILD_SCRIPT_VERSION"
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

if [ -z "$TAGS" ]; then
    echo "Error: --tags is required"
    exit 1
fi

echo "=== Build Configuration ==="
echo "Script Version: $BUILD_SCRIPT_VERSION"
echo "Registry:       $REGISTRY"
echo "Image:          $IMAGE_NAME"
echo "Base Version:   $BASE_VERSION"
echo "Tags:           $TAGS"
echo "Push:           $DO_PUSH"
echo "Podman:         $PODMAN"
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
$PODMAN build --network=host \
    --build-arg BASE_VERSION="$BASE_VERSION" \
    --build-arg FREEBSD_ARCH=amd64 \
    -t "${IMAGE_NAME}:build" .

# Show image info
echo "=== Image Info ==="
$PODMAN images | grep -E "(REPOSITORY|${IMAGE_NAME})" || true

# Push if requested
if [ "$DO_PUSH" = "true" ]; then
    # Push each tag
    echo "$TAGS" | tr ',' '\n' | while read -r TAG; do
        if [ -n "$TAG" ]; then
            echo "=== Tagging and Pushing :${TAG} ==="
            $PODMAN tag "${IMAGE_NAME}:build" "${IMAGE_NAME}:${TAG}"
            $PODMAN push "${IMAGE_NAME}:${TAG}"
        fi
    done

    echo "=== Push Complete ==="
else
    echo "=== Skipping push (use --push to push) ==="
fi
