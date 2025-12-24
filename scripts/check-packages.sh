#!/bin/sh
#
# Check FreeBSD package versions from both quarterly and latest repos
# Outputs JSON to stdout
#
# Usage: ./check-packages.sh
#
# This script must be run on a FreeBSD system with pkg installed.
# It queries both the quarterly and latest package repositories.
#
set -e

# Packages to check
PACKAGES="radarr sonarr prowlarr lidarr readarr sabnzbd tautulli jellyfin \
transmission-daemon gitea tailscale traefik vaultwarden smokeping nginx \
s6 execline sqlite3 icu nextcloud-php83"

# Output file (optional, defaults to stdout)
OUTPUT="${1:-}"

# Check if pkg is available
if ! command -v pkg >/dev/null 2>&1; then
    echo "Error: pkg command not found. This script must run on FreeBSD." >&2
    exit 1
fi

# Update package database
pkg update -q 2>/dev/null || true

# Function to get package version from a specific repo
get_version() {
    local pkg="$1"
    local repo="$2"

    if [ -n "$repo" ]; then
        pkg rquery -r "$repo" '%v' "$pkg" 2>/dev/null || echo "not_found"
    else
        pkg rquery '%v' "$pkg" 2>/dev/null || echo "not_found"
    fi
}

# Build JSON output
echo "{"
echo '  "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",'
echo '  "quarterly": {'

first=true
for pkg in $PACKAGES; do
    version=$(get_version "$pkg" "FreeBSD-quarterly" 2>/dev/null || get_version "$pkg" "" 2>/dev/null || echo "not_found")
    if [ "$first" = "true" ]; then
        first=false
    else
        echo ","
    fi
    printf '    "%s": "%s"' "$pkg" "$version"
done
echo ""
echo "  },"

echo '  "latest": {'
first=true
for pkg in $PACKAGES; do
    version=$(get_version "$pkg" "FreeBSD" 2>/dev/null || get_version "$pkg" "" 2>/dev/null || echo "not_found")
    if [ "$first" = "true" ]; then
        first=false
    else
        echo ","
    fi
    printf '    "%s": "%s"' "$pkg" "$version"
done
echo ""
echo "  }"
echo "}"
