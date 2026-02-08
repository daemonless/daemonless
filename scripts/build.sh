#!/bin/sh
#
# Shared build script for daemonless container images
# Works with both GitHub Actions (via vmactions) and Woodpecker CI
#
# Version: 1.6.0
#
# Usage: ./scripts/build.sh [OPTIONS]
#   --registry REGISTRY       Container registry (default: ghcr.io)
#   --image IMAGE             Full image name (e.g., ghcr.io/daemonless/radarr)
#   --containerfile FILE      Containerfile to use (default: Containerfile)
#   --base-version VERSION    Base image version arg (e.g., 15, 15-quarterly)
#   --pkg-repo REPO           Package repo branch (latest/quarterly)
#   --tag TAG                 Primary tag for built image (e.g., latest, pkg)
#   --tag-version             Also tag with version from /app/version
#   --version-suffix SUFFIX   Suffix for version tag (e.g., -pkg)
#   --alias ALIAS             Additional alias tag (can be used multiple times)
#   --build-arg KEY=VALUE     Additional build argument (can be used multiple times)
#   --auto-version            Auto-detect and increment dl version from registry
#   --dl-version VERSION      Explicit dl version (e.g., 15-dl3)
#   --arch ARCH               Target architecture (amd64, arm64, riscv64)
#   --push                    Push to registry (requires login first)
#   --login                   Login to registry (requires GITHUB_TOKEN env var)
#   --doas                    Use doas for podman commands
#   --skip-wip                Skip build if image is marked WIP
#   --distcc                  Use buildah with distcc/ccache for distributed compilation
#   --ccache-dir DIR          Ccache directory to mount (default: /data/ccache)
#
set -e

BUILD_SCRIPT_VERSION="1.6.0"

# Defaults
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-}"
CONTAINERFILE="Containerfile"
BASE_VERSION=""
PKG_REPO=""
TAG="latest"
TAG_VERSION="false"
VERSION_SUFFIX=""
DO_PUSH="false"
DO_LOGIN="false"
PODMAN="podman"
SKIP_WIP="false"
ALIASES=""
EXTRA_BUILD_ARGS=""
USE_DISTCC="false"
CCACHE_DIR="${CCACHE_DIR:-/data/ccache}"
AUTO_VERSION="false"
DL_VERSION=""
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
        --containerfile)
            CONTAINERFILE="$2"
            shift 2
            ;;
        --base-version)
            BASE_VERSION="$2"
            shift 2
            ;;
        --pkg-repo)
            PKG_REPO="$2"
            shift 2
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --tag-version)
            TAG_VERSION="true"
            shift
            ;;
        --version-suffix)
            VERSION_SUFFIX="$2"
            shift 2
            ;;
        --alias)
            ALIASES="$ALIASES $2"
            shift 2
            ;;
        --build-arg)
            EXTRA_BUILD_ARGS="$EXTRA_BUILD_ARGS --build-arg $2"
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
        --skip-wip)
            SKIP_WIP="true"
            shift
            ;;
        --distcc)
            USE_DISTCC="true"
            shift
            ;;
        --ccache-dir)
            CCACHE_DIR="$2"
            shift 2
            ;;
        --auto-version)
            AUTO_VERSION="true"
            shift
            ;;
        --dl-version)
            DL_VERSION="$2"
            shift 2
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --version)
            echo "build.sh version $BUILD_SCRIPT_VERSION"
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

# Check if Containerfile exists
if [ ! -f "$CONTAINERFILE" ]; then
    echo "Containerfile not found: $CONTAINERFILE"
    echo "Skipping build."
    exit 0
fi

# Check WIP flag
if [ "$SKIP_WIP" = "true" ]; then
    if grep -q 'io.daemonless.wip="true"' "$CONTAINERFILE" 2>/dev/null; then
        echo "Image is marked as WIP, skipping build."
        exit 0
    fi
fi

echo "=== Build Configuration ==="
echo "Script Version: $BUILD_SCRIPT_VERSION"
echo "Registry:       $REGISTRY"
echo "Image:          $IMAGE_NAME"
echo "Containerfile:  $CONTAINERFILE"
echo "Architecture:   $ARCH"
echo "Base Version:   ${BASE_VERSION:-default}"
echo "Pkg Repo:       ${PKG_REPO:-default}"
echo "Tag:            $TAG"
echo "Tag Version:    $TAG_VERSION"
echo "Version Suffix: $VERSION_SUFFIX"
echo "Auto Version:   $AUTO_VERSION"
echo "Push:           $DO_PUSH"
echo "Podman:         $PODMAN"
echo "Build Args:     ${EXTRA_BUILD_ARGS:-none}"
echo "Distcc:         $USE_DISTCC"
echo "Ccache Dir:     $CCACHE_DIR"
echo ""

# =============================================================================
# Auto-Version Detection (dl-number)
# =============================================================================
get_next_dl_version() {
    _image="$1"
    _tag="$2"

    # Query current version from registry using skopeo
    _current_dl=$(skopeo inspect "docker://${_image}:${_tag}" 2>/dev/null \
        | jq -r '.Labels["org.opencontainers.image.version"] // empty' \
        | sed 's/.*-dl//' || echo "")

    [ -z "$_current_dl" ] && _current_dl=0

    _new_dl=$((_current_dl + 1))
    echo "${_tag}-dl${_new_dl}"
}

if [ "$AUTO_VERSION" = "true" ] && [ -z "$DL_VERSION" ]; then
    if command -v skopeo >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        echo "=== Auto-Version Detection ==="
        # Get current version from registry
        CURRENT_DL=$(skopeo inspect "docker://${IMAGE_NAME}:${TAG}" 2>/dev/null \
            | jq -r '.Labels["org.opencontainers.image.version"] // empty' \
            | sed 's/.*-dl//' || echo "")
        [ -z "$CURRENT_DL" ] && CURRENT_DL=0

        NEW_DL=$((CURRENT_DL + 1))
        DL_VERSION="${TAG}-dl${NEW_DL}"
        echo "Previous:     dl${CURRENT_DL}"
        echo "New Version:  ${DL_VERSION}"
        echo ""
    else
        echo "Warning: skopeo or jq not found, skipping auto-version"
    fi
fi

# Login to registry
if [ "$DO_LOGIN" = "true" ]; then
    if [ -z "$GITHUB_TOKEN" ]; then
        echo "Error: GITHUB_TOKEN required for --login"
        exit 1
    fi
    echo "=== Logging in to Registry ==="
    echo "$GITHUB_TOKEN" | $PODMAN login "$REGISTRY" -u "${GITHUB_ACTOR:-daemonless}" --password-stdin
fi

# Build arguments
BUILD_ARGS="--network=host"
if [ -n "$BASE_VERSION" ]; then
    BUILD_ARGS="$BUILD_ARGS --build-arg BASE_VERSION=$BASE_VERSION"
fi
if [ -n "$PKG_REPO" ]; then
    BUILD_ARGS="$BUILD_ARGS --build-arg PKG_BRANCH=$PKG_REPO"
fi

# Map architecture names to FreeBSD convention
case "$ARCH" in
    amd64|x86_64|x64)
        FREEBSD_ARCH="amd64"
        ;;
    aarch64|arm64)
        FREEBSD_ARCH="aarch64"
        ;;
    riscv64|riscv)
        FREEBSD_ARCH="riscv64"
        ;;
    *)
        echo "Error: Unknown architecture: $ARCH"
        echo "Supported: amd64, aarch64, riscv64"
        exit 1
        ;;
esac
BUILD_ARGS="$BUILD_ARGS --build-arg FREEBSD_ARCH=$FREEBSD_ARCH"

# Forward GITHUB_TOKEN for authenticated GitHub API access (avoids rate limiting)
if [ -n "$GITHUB_TOKEN" ]; then
    BUILD_ARGS="$BUILD_ARGS --secret id=github_token,env=GITHUB_TOKEN"
fi

# Add extra build args
if [ -n "$EXTRA_BUILD_ARGS" ]; then
    BUILD_ARGS="$BUILD_ARGS $EXTRA_BUILD_ARGS"
fi

# Add dl-version as build arg if set
if [ -n "$DL_VERSION" ]; then
    BUILD_ARGS="$BUILD_ARGS --build-arg VERSION=$DL_VERSION"
fi

# Add Dynamic OCI Labels
# BUILD_DATE: RFC 3339 format
BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
# VCS_REF: Short git sha
VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

echo "=== Injecting Metadata ==="
echo "Created:  $BUILD_DATE"
echo "Revision: $VCS_REF"

BUILD_ARGS="$BUILD_ARGS --label org.opencontainers.image.created=$BUILD_DATE"
BUILD_ARGS="$BUILD_ARGS --label org.opencontainers.image.revision=$VCS_REF"
if [ -n "$DL_VERSION" ]; then
    BUILD_ARGS="$BUILD_ARGS --label org.opencontainers.image.version=$DL_VERSION"
fi

# Build image
echo "=== Building Image ==="
if [ "$USE_DISTCC" = "true" ]; then
    # Use buildah with ccache volume mount for distributed compilation
    echo "Using buildah with distcc/ccache (mounting $CCACHE_DIR)"
    BUILDAH="buildah"
    [ "$PODMAN" = "doas podman" ] && BUILDAH="doas buildah"

    # Load distcc config if available
    DISTCC_HOSTS="${DISTCC_HOSTS:-localhost}"
    [ -f /etc/distcc.conf ] && . /etc/distcc.conf
    echo "DISTCC_HOSTS: $DISTCC_HOSTS"

    $BUILDAH bud $BUILD_ARGS \
        --build-arg "DISTCC_HOSTS=$DISTCC_HOSTS" \
        -v "${CCACHE_DIR}:${CCACHE_DIR}:rw" \
        -f "$CONTAINERFILE" \
        -t "${IMAGE_NAME}:build" .
else
    $PODMAN build $BUILD_ARGS -f "$CONTAINERFILE" -t "${IMAGE_NAME}:build" .
fi

# Extract version
echo "=== Extracting Version ==="
VERSION=$($PODMAN run --rm --entrypoint="" "${IMAGE_NAME}:build" cat /app/version 2>/dev/null | sed 's/^v//' | tr -d '\n' || echo "")
echo "Version: ${VERSION:-none}"

# Add version label to image if version exists
if [ -n "$VERSION" ]; then
    echo "=== Adding Version Label ==="
    BUILDAH_CMD="buildah"
    [ "$PODMAN" = "doas podman" ] && BUILDAH_CMD="doas buildah"
    
    # Create a working container from the image
    CTR=$($BUILDAH_CMD from "${IMAGE_NAME}:build")
    
    # Apply label
    $BUILDAH_CMD config --label "org.opencontainers.image.version=${VERSION}" "$CTR"
    
    # Commit back to image
    $BUILDAH_CMD commit "$CTR" "${IMAGE_NAME}:build"
    
    # Cleanup
    $BUILDAH_CMD rm "$CTR"
fi

# Show image info
echo "=== Image Info ==="
$PODMAN images | grep -E "(REPOSITORY|${IMAGE_NAME})" || true

# Push if requested
if [ "$DO_PUSH" = "true" ]; then
    # Tag and push primary tag
    echo "=== Tagging and Pushing :${TAG} ==="
    $PODMAN tag "${IMAGE_NAME}:build" "${IMAGE_NAME}:${TAG}"
    $PODMAN push "${IMAGE_NAME}:${TAG}"

    # Tag and push dl-version if set
    if [ -n "$DL_VERSION" ]; then
        echo "=== Tagging and Pushing :${DL_VERSION} ==="
        $PODMAN tag "${IMAGE_NAME}:build" "${IMAGE_NAME}:${DL_VERSION}"
        $PODMAN push "${IMAGE_NAME}:${DL_VERSION}"
    fi

    # Tag and push version if requested and version exists (from /app/version)
    if [ "$TAG_VERSION" = "true" ] && [ -n "$VERSION" ]; then
        VTAG="${VERSION}${VERSION_SUFFIX}"
        echo "=== Tagging and Pushing :${VTAG} ==="
        $PODMAN tag "${IMAGE_NAME}:build" "${IMAGE_NAME}:${VTAG}"
        $PODMAN push "${IMAGE_NAME}:${VTAG}"
    fi

    # Tag and push aliases
    for ALIAS in $ALIASES; do
        echo "=== Tagging and Pushing Alias :${ALIAS} ==="
        $PODMAN tag "${IMAGE_NAME}:build" "${IMAGE_NAME}:${ALIAS}"
        $PODMAN push "${IMAGE_NAME}:${ALIAS}"
    done

    echo "=== Push Complete ==="
else
    echo "=== Skipping push (use --push to push) ==="
fi
