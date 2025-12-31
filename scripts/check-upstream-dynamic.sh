#!/bin/sh
#
# Dynamic version checker - reads labels from container registry
# Outputs JSON matching versions.json structure
#
# Usage: ./check-upstream-dynamic.sh [image-name]
#   If image-name provided, check only that image
#   Otherwise, check all images in ghcr.io/daemonless
#
# Requires: skopeo, jq (for JSON parsing), curl, pkg (FreeBSD)
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

    # Check upstream version using generic url + sed approach
    # Labels define both the API URL and sed expression to extract version
    url=$(echo "$labels" | jq -r '.Labels["io.daemonless.upstream-url"] // empty')
    sed_expr=$(echo "$labels" | jq -r '.Labels["io.daemonless.upstream-sed"] // empty')

    # Skip if no url or sed expression defined
    [ -z "$url" ] || [ -z "$sed_expr" ] && return

    version=$($FETCH "$url" 2>/dev/null | sed -n "$sed_expr" | head -1)
    if [ -n "$version" ]; then
        echo "${image} ${version}" >> "$UPSTREAM_DATA"
    fi
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

# List of images to check (excluding base images)
# This avoids needing GitHub API access which requires special token permissions
IMAGES="
gitea
immich-ml
immich-server
jellyfin
lidarr
mealie
n8n
nextcloud
openspeedtest
organizr
overseerr
plex
prowlarr
radarr
readarr
sabnzbd
smokeping
sonarr
tailscale
tautulli
traefik
transmission
unifi
uptime-kuma
vaultwarden
woodpecker
"

# Main
if [ -n "$1" ]; then
    # Check single image
    check_image "$1"
else
    # Update pkg database first
    pkg update -q 2>/dev/null || true

    for image in $IMAGES; do
        # Skip empty lines
        [ -z "$image" ] && continue

        echo "# Checking ${image}..." >&2
        check_image "$image"
    done
fi

output_json
