#!/bin/sh
#
# Dynamic upstream version checker
# Reads io.daemonless.upstream-* labels from container registry via skopeo
#
# Usage: ./check-upstream-dynamic.sh [image-name]
#   If image-name provided, check only that image
#   Otherwise, check all images in ghcr.io/daemonless
#
# Requires: skopeo, jq, curl (or fetch on FreeBSD)
#
set -e

REGISTRY="ghcr.io/daemonless"

# Use fetch on FreeBSD, curl elsewhere
if command -v fetch >/dev/null 2>&1; then
    FETCH="fetch -qo -"
else
    FETCH="curl -sf"
fi

# Get version from Servarr API (radarr, prowlarr, lidarr, readarr)
get_servarr_version() {
    url="$1"
    $FETCH "$url" | jq -r '.[0].version // "unknown"'
}

# Get version from Sonarr API (different format)
get_sonarr_version() {
    url="$1"
    $FETCH "$url" | jq -r '[.[] | select(.branch == "main")] | .[0].version // "unknown"'
}

# Get version from GitHub releases
get_github_version() {
    repo="$1"
    $FETCH "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name // "unknown"'
}

# Get version from npm registry
get_npm_version() {
    package="$1"
    $FETCH "https://registry.npmjs.org/${package}/latest" | jq -r '.version // "unknown"'
}

# Check a single image
check_image() {
    image="$1"

    # Get labels from registry
    labels=$(skopeo inspect "docker://${REGISTRY}/${image}:latest" 2>/dev/null) || {
        echo "${image}: error (skopeo failed)"
        return
    }

    mode=$(echo "$labels" | jq -r '.Labels["io.daemonless.upstream-mode"] // empty')

    # Skip if no upstream-mode
    [ -z "$mode" ] && return

    # Skip pkg-only images (tracked separately)
    [ "$mode" = "pkg" ] && return

    case "$mode" in
        servarr)
            url=$(echo "$labels" | jq -r '.Labels["io.daemonless.upstream-url"] // empty')
            if [ -n "$url" ]; then
                version=$(get_servarr_version "$url")
                echo "${image} ${version}"
            else
                echo "${image}: error (no upstream-url)"
            fi
            ;;
        sonarr)
            url=$(echo "$labels" | jq -r '.Labels["io.daemonless.upstream-url"] // empty')
            if [ -n "$url" ]; then
                version=$(get_sonarr_version "$url")
                echo "${image} ${version}"
            else
                echo "${image}: error (no upstream-url)"
            fi
            ;;
        github)
            repo=$(echo "$labels" | jq -r '.Labels["io.daemonless.upstream-repo"] // empty')
            if [ -n "$repo" ]; then
                version=$(get_github_version "$repo")
                echo "${image} ${version}"
            else
                echo "${image}: error (no upstream-repo)"
            fi
            ;;
        npm)
            package=$(echo "$labels" | jq -r '.Labels["io.daemonless.upstream-package"] // empty')
            if [ -n "$package" ]; then
                version=$(get_npm_version "$package")
                echo "${image} ${version}"
            else
                echo "${image}: error (no upstream-package)"
            fi
            ;;
        source|ubiquiti)
            # Skip - requires manual handling
            ;;
        *)
            echo "${image}: unknown mode (${mode})"
            ;;
    esac
}

# Main
if [ -n "$1" ]; then
    # Check single image
    check_image "$1"
else
    # Get all images from registry
    images=$(gh api orgs/daemonless/packages?package_type=container --jq '.[].name' 2>/dev/null) || {
        echo "Error: Failed to list packages (need gh CLI authenticated)" >&2
        exit 1
    }

    for image in $images; do
        # Skip base images
        case "$image" in
            base|arr-base|nginx-base) continue ;;
        esac

        check_image "$image"
    done
fi
