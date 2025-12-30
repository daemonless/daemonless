#!/bin/sh
#
# Dynamic version checker - reads labels from container registry
# Outputs JSON matching versions.json structure
#
# Usage: ./check-upstream-dynamic.sh [image-name]
#   If image-name provided, check only that image
#   Otherwise, check all images in ghcr.io/daemonless
#
# Requires: skopeo, jq, gh, pkg (FreeBSD)
#
set -e

REGISTRY="ghcr.io/daemonless"

# Use fetch on FreeBSD, curl elsewhere
if command -v fetch >/dev/null 2>&1; then
    FETCH="fetch -qo -"
else
    FETCH="curl -sf"
fi

# Temporary files for collecting data
QUARTERLY_DATA=$(mktemp)
LATEST_DATA=$(mktemp)
UPSTREAM_DATA=$(mktemp)
trap "rm -f $QUARTERLY_DATA $LATEST_DATA $UPSTREAM_DATA" EXIT

# Get version from FreeBSD quarterly repo
get_pkg_quarterly() {
    # Try quarterly repo first, fall back to FreeBSD-quarterly name
    pkg rquery -r quarterly '%v' "$1" 2>/dev/null || \
    pkg rquery -r FreeBSD-quarterly '%v' "$1" 2>/dev/null || \
    echo "not_found"
}

# Get version from FreeBSD latest repo
get_pkg_latest() {
    # Try latest repo first, fall back to FreeBSD name, then default
    pkg rquery -r latest '%v' "$1" 2>/dev/null || \
    pkg rquery -r FreeBSD '%v' "$1" 2>/dev/null || \
    pkg rquery '%v' "$1" 2>/dev/null || \
    echo "not_found"
}

# Get version from Servarr API (radarr, prowlarr, lidarr, readarr)
get_servarr_version() {
    $FETCH "$1" 2>/dev/null | jq -r '.[0].version // "unknown"'
}

# Get version from Sonarr API (different format)
get_sonarr_version() {
    $FETCH "$1" 2>/dev/null | jq -r '[.[] | select(.branch == "main")] | .[0].version // "unknown"'
}

# Get version from GitHub releases
get_github_version() {
    $FETCH "https://api.github.com/repos/${1}/releases/latest" 2>/dev/null | jq -r '.tag_name // "unknown"'
}

# Get version from npm registry
get_npm_version() {
    $FETCH "https://registry.npmjs.org/${1}/latest" 2>/dev/null | jq -r '.version // "unknown"'
}

# Check a single image and collect data
check_image() {
    image="$1"

    # Check :pkg tag for package name (for quarterly/latest tracking)
    pkg_labels=$(skopeo inspect "docker://${REGISTRY}/${image}:pkg" 2>/dev/null || true)
    if [ -n "$pkg_labels" ]; then
        pkg_name=$(echo "$pkg_labels" | jq -r '.Labels["io.daemonless.pkg-name"] // empty')
        if [ -n "$pkg_name" ]; then
            # Check quarterly and latest versions
            q_ver=$(get_pkg_quarterly "$pkg_name")
            l_ver=$(get_pkg_latest "$pkg_name")

            echo "${image} ${q_ver}" >> "$QUARTERLY_DATA"
            echo "${image} ${l_ver}" >> "$LATEST_DATA"
        fi
    fi

    # Check :latest tag for upstream version
    labels=$(skopeo inspect "docker://${REGISTRY}/${image}:latest" 2>/dev/null) || {
        echo "# ${image}: skopeo failed for :latest" >&2
        return
    }

    # Check upstream version based on mode
    mode=$(echo "$labels" | jq -r '.Labels["io.daemonless.upstream-mode"] // empty')
    [ -z "$mode" ] && return

    case "$mode" in
        pkg)
            # pkg-only mode - no upstream to check, already handled above
            ;;
        servarr)
            url=$(echo "$labels" | jq -r '.Labels["io.daemonless.upstream-url"] // empty')
            if [ -n "$url" ]; then
                version=$(get_servarr_version "$url")
                echo "${image} ${version}" >> "$UPSTREAM_DATA"
            fi
            ;;
        sonarr)
            url=$(echo "$labels" | jq -r '.Labels["io.daemonless.upstream-url"] // empty')
            if [ -n "$url" ]; then
                version=$(get_sonarr_version "$url")
                echo "${image} ${version}" >> "$UPSTREAM_DATA"
            fi
            ;;
        github)
            repo=$(echo "$labels" | jq -r '.Labels["io.daemonless.upstream-repo"] // empty')
            if [ -n "$repo" ]; then
                version=$(get_github_version "$repo")
                echo "${image} ${version}" >> "$UPSTREAM_DATA"
            fi
            ;;
        npm)
            package=$(echo "$labels" | jq -r '.Labels["io.daemonless.upstream-package"] // empty')
            if [ -n "$package" ]; then
                version=$(get_npm_version "$package")
                echo "${image} ${version}" >> "$UPSTREAM_DATA"
            fi
            ;;
        source|ubiquiti)
            # Skip - requires manual handling
            ;;
        *)
            echo "# ${image}: unknown mode (${mode})" >&2
            ;;
    esac
}

# Output JSON from collected data
output_json() {
    echo "{"
    echo "  \"packages\": {"

    # Quarterly section
    echo "    \"quarterly\": {"
    first=true
    if [ -s "$QUARTERLY_DATA" ]; then
        while read -r img ver; do
            [ -z "$img" ] && continue
            [ "$ver" = "not_found" ] && continue
            if [ "$first" = "true" ]; then
                first=false
            else
                printf ",\n"
            fi
            printf "      \"%s\": \"%s\"" "$img" "$ver"
        done < "$QUARTERLY_DATA"
    fi
    echo ""
    echo "    },"

    # Latest section
    echo "    \"latest\": {"
    first=true
    if [ -s "$LATEST_DATA" ]; then
        while read -r img ver; do
            [ -z "$img" ] && continue
            [ "$ver" = "not_found" ] && continue
            if [ "$first" = "true" ]; then
                first=false
            else
                printf ",\n"
            fi
            printf "      \"%s\": \"%s\"" "$img" "$ver"
        done < "$LATEST_DATA"
    fi
    echo ""
    echo "    }"

    echo "  },"

    # Upstream section
    echo "  \"upstream\": {"
    first=true
    if [ -s "$UPSTREAM_DATA" ]; then
        while read -r img ver; do
            [ -z "$img" ] && continue
            [ "$ver" = "unknown" ] && continue
            if [ "$first" = "true" ]; then
                first=false
            else
                printf ",\n"
            fi
            printf "    \"%s\": \"%s\"" "$img" "$ver"
        done < "$UPSTREAM_DATA"
    fi
    echo ""
    echo "  }"

    echo "}"
}

# Main
if [ -n "$1" ]; then
    # Check single image
    check_image "$1"
else
    # Update pkg database first
    pkg update -q 2>/dev/null || true

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

        echo "# Checking ${image}..." >&2
        check_image "$image"
    done
fi

output_json
