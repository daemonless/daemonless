#!/bin/sh
#
# Check upstream release versions from various APIs
# Outputs JSON to stdout
#
# Usage: ./check-upstream.sh
#
# Requires: curl, jq (or python3 for JSON parsing)
#
set -e

# Use jq if available, otherwise fall back to python3
if command -v jq >/dev/null 2>&1; then
    JSON_PARSER="jq"
else
    JSON_PARSER="python3"
fi

# Function to extract version from Servarr API
get_servarr_version() {
    local url="$1"
    local result
    result=$(curl -sf "$url" 2>/dev/null) || { echo "error"; return; }

    if [ "$JSON_PARSER" = "jq" ]; then
        echo "$result" | jq -r '.[0].version // "unknown"'
    else
        echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['version'] if d else 'unknown')" 2>/dev/null || echo "error"
    fi
}

# Function to extract version from GitHub releases API
get_github_version() {
    local repo="$1"
    local result
    result=$(curl -sf "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null) || { echo "error"; return; }

    if [ "$JSON_PARSER" = "jq" ]; then
        echo "$result" | jq -r '.tag_name // "unknown"'
    else
        echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tag_name', 'unknown'))" 2>/dev/null || echo "error"
    fi
}

# Function to get latest commit SHA from GitHub
get_github_commit() {
    local repo="$1"
    local branch="${2:-main}"
    local result
    result=$(curl -sf "https://api.github.com/repos/${repo}/commits/${branch}" 2>/dev/null) || { echo "error"; return; }

    if [ "$JSON_PARSER" = "jq" ]; then
        echo "$result" | jq -r '.sha[:7] // "unknown"'
    else
        echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('sha', 'unknown')[:7])" 2>/dev/null || echo "error"
    fi
}

# Function to get npm package version
get_npm_version() {
    local pkg="$1"
    local result
    result=$(curl -sf "https://registry.npmjs.org/${pkg}/latest" 2>/dev/null) || { echo "error"; return; }

    if [ "$JSON_PARSER" = "jq" ]; then
        echo "$result" | jq -r '.version // "unknown"'
    else
        echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('version', 'unknown'))" 2>/dev/null || echo "error"
    fi
}

# Function to get Sonarr version (different API structure)
get_sonarr_version() {
    local result
    result=$(curl -sf "https://services.sonarr.tv/v1/releases" 2>/dev/null) || { echo "error"; return; }

    if [ "$JSON_PARSER" = "jq" ]; then
        echo "$result" | jq -r '[.[] | select(.branch == "main")] | .[0].version // "unknown"'
    else
        echo "$result" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d:
    if isinstance(r, dict) and r.get('branch') == 'main':
        print(r.get('version', 'unknown'))
        sys.exit(0)
print('unknown')
" 2>/dev/null || echo "error"
    fi
}

# Build JSON output
echo "{"
echo '  "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",'
echo '  "versions": {'

# Servarr apps
printf '    "radarr": "%s",\n' "$(get_servarr_version 'https://radarr.servarr.com/v1/update/master/changes?os=bsd')"
printf '    "sonarr": "%s",\n' "$(get_sonarr_version)"
printf '    "prowlarr": "%s",\n' "$(get_servarr_version 'https://prowlarr.servarr.com/v1/update/master/changes?os=bsd')"
printf '    "lidarr": "%s",\n' "$(get_servarr_version 'https://lidarr.servarr.com/v1/update/master/changes?os=bsd')"
printf '    "readarr": "%s",\n' "$(get_servarr_version 'https://readarr.servarr.com/v1/update/develop/changes?os=bsd')"

# GitHub releases
printf '    "sabnzbd": "%s",\n' "$(get_github_version 'sabnzbd/sabnzbd')"
printf '    "tautulli": "%s",\n' "$(get_github_version 'Tautulli/Tautulli')"
printf '    "jellyfin": "%s",\n' "$(get_github_version 'jellyfin/jellyfin')"
printf '    "traefik": "%s",\n' "$(get_github_version 'traefik/traefik')"
printf '    "mealie": "%s",\n' "$(get_github_version 'mealie-recipes/mealie')"
printf '    "woodpecker": "%s",\n' "$(get_github_version 'woodpecker-ci/woodpecker')"
printf '    "openspeedtest": "%s",\n' "$(get_github_version 'openspeedtest/OpenSpeedTest')"
printf '    "smokeping": "%s",\n' "$(get_github_version 'oetiker/SmokePing')"

# GitHub commits (for develop branches)
printf '    "overseerr": "%s",\n' "$(get_github_commit 'sct/overseerr' 'develop')"

# npm packages
printf '    "n8n": "%s"\n' "$(get_npm_version 'n8n')"

echo "  }"
echo "}"
