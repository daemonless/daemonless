#!/bin/sh
#
# dbuild CI wrapper for Woodpecker
# Locates dbuild and runs the full pipeline: build → test → push → sbom
#
# Usage: sh dbuild-ci.sh [VARIANT]
#
# Env vars:
#   DBUILD_PATH  - explicit path to dbuild checkout (optional)
#   GITHUB_TOKEN - registry authentication
#   GITHUB_ACTOR - registry username (optional)
#

set -e

# ── Locate dbuild ────────────────────────────────────────────────────

if [ -n "$DBUILD_PATH" ] && [ -d "$DBUILD_PATH/dbuild" ]; then
    DBUILD_DIR="$DBUILD_PATH"
elif [ -d "../dbuild/dbuild" ]; then
    DBUILD_DIR="$(cd ../dbuild && pwd)"
elif [ -d "/home/ahze/src/daemonless/dbuild/dbuild" ]; then
    DBUILD_DIR="/home/ahze/src/daemonless/dbuild"
else
    echo "Fetching dbuild from GitHub..."
    fetch -qo /tmp/dbuild.tar.gz \
        "https://github.com/daemonless/dbuild/archive/refs/heads/main.tar.gz"
    tar -xzf /tmp/dbuild.tar.gz -C /tmp
    DBUILD_DIR="/tmp/dbuild-main"
fi

export PYTHONPATH="$DBUILD_DIR"
DBUILD="python3 -m dbuild"

echo "=== dbuild CI ==="
echo "dbuild path: $DBUILD_DIR"
$DBUILD --version

# ── Variant filter (optional) ────────────────────────────────────────

VARIANT_FLAG=""
if [ -n "$1" ]; then
    VARIANT_FLAG="--variant $1"
fi

# ── Pipeline ─────────────────────────────────────────────────────────

# Build
$DBUILD -v build $VARIANT_FLAG

# Test
$DBUILD -v test $VARIANT_FLAG --json cit-result.json

# Push (push.py handles CI detection and PR skip)
$DBUILD -v push $VARIANT_FLAG

# SBOM
$DBUILD -v sbom $VARIANT_FLAG

echo "=== dbuild CI complete ==="
