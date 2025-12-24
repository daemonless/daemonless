#!/bin/sh
# Build all FreeBSD container images
# Usage: ./scripts/local-build.sh [15|14] [image-name] [tag] [arch]
#
# Tags:
#   latest      - Download from upstream (default)
#   pkg         - FreeBSD quarterly packages
#   pkg-latest  - FreeBSD latest packages
#
# Architectures:
#   amd64       - x86_64 (default)
#   arm64       - aarch64 (Pi4, etc)
#
# Examples:
#   ./scripts/local-build.sh 15 radarr latest
#   ./scripts/local-build.sh 15 radarr pkg
#   ./scripts/local-build.sh 15 all pkg
#   ./scripts/local-build.sh 15 sabnzbd pkg arm64
#   ./scripts/local-build.sh 15 sabnzbd latest arm64
#   ./scripts/local-build.sh 15 all latest arm64
#
# ARM64 support is determined by io.daemonless.arch label in Containerfile

set -e

FREEBSD_VERSION="${1:-15}"
IMAGE="${2:-all}"
TAG="${3:-latest}"
ARCH="${4:-amd64}"

# Map arch names
case "$ARCH" in
    amd64|x86_64|x64)
        ARCH="amd64"
        FREEBSD_ARCH="amd64"
        ;;
    arm64|aarch64)
        ARCH="arm64"
        FREEBSD_ARCH="aarch64"
        ;;
    *)
        echo "Error: Unknown architecture: $ARCH"
        echo "Supported: amd64, arm64"
        exit 1
        ;;
esac

echo "Building for FreeBSD ${FREEBSD_VERSION} (${ARCH}), tag: ${TAG}"

# Pkg cache - disabled due to older podman version
# PKG_CACHE_MOUNT="-v /var/cache/pkg:/var/cache/pkg"

# Check if image is marked as WIP via io.daemonless.wip label
# Usage: is_wip <image-name>
# Returns 0 if WIP, 1 if not
is_wip() {
    local name="$1"
    local containerfile="../repos/${name}/Containerfile"

    if [ ! -f "$containerfile" ]; then
        return 1
    fi

    grep -q 'io.daemonless.wip="true"' "$containerfile"
}

# Check if image supports a given architecture by reading io.daemonless.arch label
# Usage: supports_arch <image-name> <arch>
# Returns 0 if supported, 1 if not
supports_arch() {
    local name="$1"
    local arch="$2"
    local containerfile="../repos/${name}/Containerfile"

    if [ ! -f "$containerfile" ]; then
        return 1
    fi

    # Extract arch label from Containerfile
    local arch_label=$(grep 'io.daemonless.arch=' "$containerfile" | sed 's/.*io.daemonless.arch="\([^"]*\)".*/\1/')

    # Default to amd64 if no label found
    if [ -z "$arch_label" ]; then
        arch_label="amd64"
    fi

    # Check if requested arch is in the label
    echo "$arch_label" | grep -q "$arch"
}

# Determine pkg branch based on tag
case "$TAG" in
    pkg)
        PKG_BRANCH="quarterly"
        ;;
    pkg-latest)
        PKG_BRANCH="latest"
        ;;
    *)
        PKG_BRANCH="latest"
        ;;
esac

# Build base image
build_base() {
    local branch="$1"
    local base_tag="${FREEBSD_VERSION}"
    [ "$branch" = "quarterly" ] && base_tag="${FREEBSD_VERSION}-quarterly"
    [ "$ARCH" = "arm64" ] && base_tag="${base_tag}-arm64"

    echo "==> Building base image: base-image:${base_tag} (pkg branch: ${branch}, arch: ${ARCH})"
    podman build --network=host \
        --build-arg "PKG_BRANCH=${branch}" \
        --build-arg "FREEBSD_ARCH=${FREEBSD_ARCH}" \
        -t "base-image:${base_tag}" \
        -t "localhost/base-image:${base_tag}" \
        "../repos/base-image/${FREEBSD_VERSION}/"
}

# Track which base images have been built
NGINX_BASE_BUILT=""

# Build nginx base image
build_nginx_base() {
    local base_version="${FREEBSD_VERSION}"
    [ "$TAG" = "pkg" ] && base_version="${FREEBSD_VERSION}-quarterly"
    [ "$ARCH" = "arm64" ] && base_version="${base_version}-arm64"

    # Only build once per run
    if [ "$NGINX_BASE_BUILT" = "$base_version" ]; then
        return
    fi

    echo "==> Building nginx base image: nginx-base-image:${base_version}"
    podman build --network=host \
        --build-arg "BASE_VERSION=${base_version}" \
        -t "nginx-base-image:${base_version}" \
        -t "localhost/nginx-base-image:${base_version}" \
        "../repos/nginx-base-image/"

    NGINX_BASE_BUILT="$base_version"
}

# Check if image uses main Containerfile for pkg builds (io.daemonless.pkg-source="containerfile")
# This means no separate Containerfile.pkg - use same file with different base
uses_main_containerfile_for_pkg() {
    local containerfile="../repos/$1/Containerfile"
    [ -f "$containerfile" ] && grep -q 'io.daemonless.pkg-source="containerfile"' "$containerfile"
}

# Check if image needs nginx base (io.daemonless.base="nginx")
needs_nginx_base() {
    local containerfile="../repos/$1/Containerfile"
    [ -f "$containerfile" ] && grep -q 'io.daemonless.base="nginx"' "$containerfile"
}

# Build app image
build_image() {
    local name="$1"
    local tag="$2"
    local containerfile="../repos/${name}/Containerfile"
    local base_version="${FREEBSD_VERSION}"
    local image_tag="$tag"

    # Check architecture support via label
    if [ "$ARCH" = "arm64" ]; then
        if ! supports_arch "$name" "arm64"; then
            echo "==> Skipping ${name}: not supported on ARM64 (check io.daemonless.arch label)"
            return
        fi
        image_tag="${tag}-arm64"
    fi

    # For pkg tags, use Containerfile.pkg if it exists, or main Containerfile if labeled
    if [ "$tag" = "pkg" ] || [ "$tag" = "pkg-latest" ]; then
        if [ -f "../repos/${name}/Containerfile.pkg" ]; then
            containerfile="../repos/${name}/Containerfile.pkg"
            # Use quarterly base for :pkg tag
            [ "$tag" = "pkg" ] && base_version="${FREEBSD_VERSION}-quarterly"
        elif uses_main_containerfile_for_pkg "$name"; then
            # Use main Containerfile with appropriate base
            containerfile="../repos/${name}/Containerfile"
            [ "$tag" = "pkg" ] && base_version="${FREEBSD_VERSION}-quarterly"
        else
            echo "==> Skipping ${name}: no Containerfile.pkg"
            return
        fi
    else
        # For :latest tag, check Containerfile exists
        if [ ! -f "$containerfile" ]; then
            echo "==> Skipping ${name}: no Containerfile"
            return
        fi
    fi

    # Build nginx base if needed (detected from Containerfile label)
    if needs_nginx_base "$name"; then
        build_nginx_base
    fi

    # Add arm64 suffix to base version
    [ "$ARCH" = "arm64" ] && base_version="${base_version}-arm64"

    echo "==> Building image: ${name}:${image_tag}"
    podman build --network=host \
        --build-arg "BASE_VERSION=${base_version}" \
        -f "$containerfile" \
        -t "${name}:${image_tag}" \
        -t "localhost/${name}:${image_tag}" \
        "../repos/${name}/"

    # For images using main Containerfile for pkg, :pkg-latest is alias for :latest
    # (both use latest base, so they produce identical images)
    if [ "$tag" = "latest" ] && uses_main_containerfile_for_pkg "$name"; then
        local alias_tag="pkg-latest"
        [ "$ARCH" = "arm64" ] && alias_tag="pkg-latest-arm64"
        echo "==> Tagging ${name}:${image_tag} as ${name}:${alias_tag}"
        podman tag "localhost/${name}:${image_tag}" "localhost/${name}:${alias_tag}"
    fi
}

# Build appropriate base image
if [ "$TAG" = "pkg" ]; then
    build_base "quarterly"
else
    build_base "latest"
fi

# Build requested image(s)
if [ "$IMAGE" = "all" ]; then
    # Build all images (skip WIP)
    for dir in ../repos/*/; do
        name=$(basename "$dir")
        if [ "$name" = "base-image" ] || [ "$name" = "nginx-base-image" ]; then
            continue
        fi
        if is_wip "$name"; then
            echo "==> Skipping ${name}: marked as WIP (io.daemonless.wip)"
            continue
        fi
        build_image "$name" "$TAG"
    done
else
    build_image "$IMAGE" "$TAG"
fi

echo "==> Build complete"
podman images localhost/*
