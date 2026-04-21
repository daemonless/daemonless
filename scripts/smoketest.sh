#!/bin/sh
# smoketest.sh — Check running containers; optionally pull latest images and purge old ones.
#
# Usage:
#   smoketest.sh [--pull-purge]
#
# Without flags: report running containers and their health status.
# With --pull-purge: pull latest image for every running container, then prune dangling images.

set -e

PULL_PURGE=0

for arg in "$@"; do
    case "$arg" in
        --pull-purge) PULL_PURGE=1 ;;
        --help|-h)
            echo "Usage: $0 [--pull-purge]"
            echo "  --pull-purge  Pull latest images for running containers and prune old ones"
            exit 0
            ;;
        *)
            echo "Unknown flag: $arg" >&2
            exit 1
            ;;
    esac
done

# Detect privilege escalation needed
if [ "$(id -u)" -ne 0 ]; then
    SUDO="doas"
else
    SUDO=""
fi

PODMAN="$SUDO podman"

echo "==> Running containers"
$PODMAN ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | column -t
echo ""

if [ "$PULL_PURGE" -eq 1 ]; then
    echo "==> Pulling latest images for all running containers"

    # Get unique images from running containers
    IMAGES=$($PODMAN ps --format '{{.Image}}' | sort -u)

    if [ -z "$IMAGES" ]; then
        echo "No running containers found."
    else
        FAILED=0
        for image in $IMAGES; do
            printf "  Pulling %s ... " "$image"
            if $PODMAN pull "$image" >/dev/null 2>&1; then
                echo "OK"
            else
                echo "FAILED"
                FAILED=$((FAILED + 1))
            fi
        done

        if [ "$FAILED" -gt 0 ]; then
            echo "  WARNING: $FAILED image(s) failed to pull" >&2
        fi
    fi

    echo ""
    echo "==> Pruning dangling images"
    $PODMAN image prune -f
    echo ""

    echo "==> Image summary"
    $PODMAN images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" | column -t
    echo ""
fi

echo "==> Health check"
UNHEALTHY=0
for name in $($PODMAN ps --format '{{.Names}}'); do
    status=$($PODMAN inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo "unknown")
    health=$($PODMAN inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$name" 2>/dev/null || echo "unknown")
    if [ "$status" = "running" ]; then
        if [ "$health" = "unhealthy" ]; then
            echo "  UNHEALTHY: $name (health=$health)"
            UNHEALTHY=$((UNHEALTHY + 1))
        else
            echo "  OK: $name (status=$status, health=$health)"
        fi
    else
        echo "  WARN: $name not running (status=$status)"
        UNHEALTHY=$((UNHEALTHY + 1))
    fi
done

echo ""
if [ "$UNHEALTHY" -gt 0 ]; then
    echo "==> RESULT: $UNHEALTHY container(s) unhealthy or not running" >&2
    exit 1
else
    echo "==> RESULT: All containers healthy"
fi
