#!/bin/sh
#
# Shared build script for daemonless base image
# Works with both GitHub Actions (via vmactions) and Woodpecker CI
#
# Version: 1.1.0
#
# Usage: ./scripts/build-base.sh [OPTIONS]
#   --registry REGISTRY       Container registry (default: ghcr.io)
#   --image IMAGE             Full image name (e.g., ghcr.io/daemonless/base)
#   --freebsd-version VER     FreeBSD major version (14 or 15)
#   --pkg-branch BRANCH       Package branch: latest or quarterly
#   --push-latest             Also push :latest tag (only for primary build)
#   --arch ARCH               Target architecture (amd64, arm64, riscv64)
#   --push                    Push to registry
#   --login                   Login to registry (requires GITHUB_TOKEN env var)
#   --doas                    Use doas for podman commands
#
set -e

BUILD_SCRIPT_VERSION="1.1.0"

# Defaults
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-}"
FREEBSD_VERSION="15"
PKG_BRANCH="latest"
PUSH_LATEST="false"
DO_PUSH="false"
DO_LOGIN="false"
PODMAN="podman"
ARCH="amd64"

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
        --arch)
            ARCH="$2"
            shift 2
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

# Build directory - check for version subdirectory or use current directory
if [ -d "${FREEBSD_VERSION}" ]; then
    BUILD_DIR="${FREEBSD_VERSION}"
elif [ -f "Containerfile" ]; then
    BUILD_DIR="."
else
    echo "Error: No Containerfile found (checked ${FREEBSD_VERSION}/ and ./)"
    exit 1
fi

# Map architecture names to FreeBSD convention
case "$ARCH" in
    amd64|x86_64|x64)
        FREEBSD_ARCH="amd64"
        ARCH_SUFFIX=""
        ;;
    aarch64|arm64)
        FREEBSD_ARCH="aarch64"
        ARCH_SUFFIX="-aarch64"
        ;;
    riscv64|riscv)
        FREEBSD_ARCH="riscv64"
        ARCH_SUFFIX="-riscv64"
        ;;
    *)
        echo "Error: Unknown architecture: $ARCH"
        echo "Supported: amd64, aarch64, riscv64"
        exit 1
        ;;
esac

# Determine tags
# quarterly = stable default (:15), latest = bleeding edge (:15-latest)
if [ "$PKG_BRANCH" = "quarterly" ]; then
    PRIMARY_TAG="${FREEBSD_VERSION}${ARCH_SUFFIX}"
    ALIAS_TAG="${FREEBSD_VERSION}-quarterly${ARCH_SUFFIX}"
else
    PRIMARY_TAG="${FREEBSD_VERSION}-latest${ARCH_SUFFIX}"
    ALIAS_TAG=""
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
echo "Architecture:    $ARCH ($FREEBSD_ARCH)"
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
    --build-arg FREEBSD_ARCH="$FREEBSD_ARCH" \
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
    # Push primary tag (e.g., :15 for quarterly, :15-latest for latest)
    echo "=== Tagging and Pushing :${PRIMARY_TAG} ==="
    $PODMAN tag "${IMAGE_NAME}:build" "${IMAGE_NAME}:${PRIMARY_TAG}"
    $PODMAN push "${IMAGE_NAME}:${PRIMARY_TAG}"

    # Push alias tag if set (e.g., :15-quarterly for quarterly builds)
    if [ -n "$ALIAS_TAG" ]; then
        echo "=== Tagging and Pushing :${ALIAS_TAG} ==="
        $PODMAN tag "${IMAGE_NAME}:build" "${IMAGE_NAME}:${ALIAS_TAG}"
        $PODMAN push "${IMAGE_NAME}:${ALIAS_TAG}"
    fi

    # Push full version tag (e.g., :15.0-RELEASE-p1) - only for quarterly (stable)
    if [ "$PKG_BRANCH" = "quarterly" ] && [ -n "$VERSION" ]; then
        echo "=== Tagging and Pushing :${VERSION} ==="
        $PODMAN tag "${IMAGE_NAME}:build" "${IMAGE_NAME}:${VERSION}"
        $PODMAN push "${IMAGE_NAME}:${VERSION}"
    fi

    # Push :latest if requested (for quarterly/stable builds)
    if [ "$PUSH_LATEST" = "true" ]; then
        echo "=== Pushing :latest ==="
        $PODMAN tag "${IMAGE_NAME}:build" "${IMAGE_NAME}:latest"
        $PODMAN push "${IMAGE_NAME}:latest"
    fi

    echo "=== Push Complete ==="
else
    echo "=== Skipping push (use --push to push) ==="
fi
