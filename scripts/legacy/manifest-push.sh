#!/bin/sh
#
# Create and push multi-arch manifest for daemonless container images
#
# Version: 1.0.0
#
# Usage: ./scripts/manifest-push.sh [OPTIONS]
#   --registry REGISTRY       Container registry (default: ghcr.io)
#   --image IMAGE             Full image name (e.g., ghcr.io/daemonless/radarr)
#   --tag TAG                 Base tag (e.g., latest, 11.4)
#   --architectures ARCHS     Space-separated architectures (default: "amd64")
#   --push                    Push manifest to registry
#   --login                   Login to registry (requires GITHUB_TOKEN env var)
#   --doas                    Use doas for podman commands
#
set -e

SCRIPT_VERSION="1.0.0"

# Defaults
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-}"
TAG=""
ARCHITECTURES="amd64"
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
        --tag)
            TAG="$2"
            shift 2
            ;;
        --architectures)
            ARCHITECTURES="$2"
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
            echo "manifest-push.sh version $SCRIPT_VERSION"
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

if [ -z "$TAG" ]; then
    echo "Error: --tag is required"
    exit 1
fi

echo "=== Manifest Configuration ==="
echo "Script Version: $SCRIPT_VERSION"
echo "Registry:       $REGISTRY"
echo "Image:          $IMAGE_NAME"
echo "Base Tag:       $TAG"
echo "Architectures:  $ARCHITECTURES"
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

# Build list of arch-specific images
MANIFEST_IMAGES=""
for arch in $ARCHITECTURES; do
    case "$arch" in
        amd64)
            ARCH_TAG="${TAG}"
            ;;
        arm64)
            ARCH_TAG="${TAG}-arm64"
            ;;
        riscv64)
            ARCH_TAG="${TAG}-riscv64"
            ;;
        *)
            echo "Warning: Unknown architecture $arch, skipping"
            continue
            ;;
    esac

    FULL_IMAGE="${IMAGE_NAME}:${ARCH_TAG}"

    # Check if image exists
    if $PODMAN manifest exists "${FULL_IMAGE}" 2>/dev/null || \
       $PODMAN image exists "${FULL_IMAGE}" 2>/dev/null || \
       skopeo inspect "docker://${FULL_IMAGE}" >/dev/null 2>&1; then
        echo "Found: ${FULL_IMAGE}"
        MANIFEST_IMAGES="$MANIFEST_IMAGES $FULL_IMAGE"
    else
        echo "Not found: ${FULL_IMAGE} (skipping)"
    fi
done

if [ -z "$MANIFEST_IMAGES" ]; then
    echo "Error: No architecture-specific images found"
    exit 1
fi

echo ""
echo "=== Creating Manifest ==="
MANIFEST_NAME="${IMAGE_NAME}:${TAG}"

# Remove existing manifest if present
$PODMAN manifest rm "${MANIFEST_NAME}" 2>/dev/null || true

# Create new manifest
$PODMAN manifest create "${MANIFEST_NAME}"

# Add each architecture image
for img in $MANIFEST_IMAGES; do
    echo "Adding: $img"
    $PODMAN manifest add "${MANIFEST_NAME}" "docker://${img}"
done

# Inspect manifest
echo ""
echo "=== Manifest Contents ==="
$PODMAN manifest inspect "${MANIFEST_NAME}" | jq -r '.manifests[] | "\(.platform.architecture): \(.digest[0:20])..."'

# Push if requested
if [ "$DO_PUSH" = "true" ]; then
    echo ""
    echo "=== Pushing Manifest ==="
    $PODMAN manifest push --all "${MANIFEST_NAME}" "docker://${MANIFEST_NAME}"
    echo "Pushed: ${MANIFEST_NAME}"
else
    echo ""
    echo "=== Skipping push (use --push to push) ==="
fi
