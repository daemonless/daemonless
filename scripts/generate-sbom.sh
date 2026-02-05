#!/bin/sh
#
# Generate CycloneDX SBOM for FreeBSD container images
#
# Version: 1.0.0
#
# Usage: ./scripts/generate-sbom.sh [OPTIONS]
#   --image IMAGE           Full image reference to scan (required)
#   --image-name NAME       Short image name (required)
#   --tag TAG               Image tag (required)
#   --arch ARCH             Architecture (required)
#   --source SOURCE         Source type: upstream-binary, freebsd-quarterly, freebsd-latest
#   --output-dir DIR        Output directory (default: sbom-results)
#   --doas                  Use doas for podman commands
#
set -e

SBOM_VERSION="1.0.0"

# Defaults
IMAGE=""
IMAGE_NAME=""
TAG=""
ARCH=""
SOURCE=""
OUTPUT_DIR="sbom-results"
PODMAN="podman"

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2 ;;
    --image-name) IMAGE_NAME="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --arch) ARCH="$2"; shift 2 ;;
    --source) SOURCE="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --doas) PODMAN="doas podman"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Validate required args
if [ -z "$IMAGE" ] || [ -z "$IMAGE_NAME" ] || [ -z "$TAG" ] || [ -z "$ARCH" ]; then
  echo "ERROR: --image, --image-name, --tag, and --arch are required"
  exit 1
fi

# Auto-detect source if not provided
if [ -z "$SOURCE" ]; then
  case "$TAG" in
    *pkg-latest*) SOURCE="freebsd-latest" ;;
    *pkg*) SOURCE="freebsd-quarterly" ;;
    *) SOURCE="upstream-binary" ;;
  esac
fi

echo "=== Generating SBOM (v$SBOM_VERSION) ==="
echo "Image: $IMAGE"
echo "Tag: $TAG"
echo "Arch: $ARCH"
echo "Source: $SOURCE"

mkdir -p "$OUTPUT_DIR"
SBOM_FILE="$OUTPUT_DIR/${IMAGE_NAME}-${TAG}-sbom.json"

# Get app version
APP_VERSION=$($PODMAN run --rm --entrypoint sh "$IMAGE" -c 'cat /app/version 2>/dev/null || pkg query "%v" $(pkg query -e "%At = title" "%n") 2>/dev/null | head -1 || echo "unknown"' 2>/dev/null || echo "unknown")
echo "App version: $APP_VERSION"

# Save image to tar for Trivy (--image-src podman needs socket, tar works everywhere)
echo "Saving image to tar..."
$PODMAN save "$IMAGE" -o /tmp/image-scan.tar

# Generate CycloneDX with Trivy (detects Node, Python, .NET, Go, etc.)
echo "Running Trivy scan..."
trivy image --input /tmp/image-scan.tar --format cyclonedx --scanners vuln \
  --output /tmp/trivy-sbom.json 2>&1 || echo '{"components":[]}' > /tmp/trivy-sbom.json

# Extract FreeBSD packages (Trivy doesn't detect pkg)
echo "Extracting FreeBSD packages..."
$PODMAN run --rm --entrypoint sh "$IMAGE" -c 'pkg query "%n %v %c"' 2>/dev/null | \
  tr -cd '[:print:]\n' > /tmp/freebsd_raw.txt || true

# Convert FreeBSD packages to CycloneDX components
jq -Rs '
  split("\n") | map(select(length > 0)) | map(
    split(" ") | {
      type: "library",
      "bom-ref": ("pkg:freebsd/" + .[0] + "@" + .[1]),
      name: .[0],
      version: .[1],
      description: (.[2:] | join(" ")),
      purl: ("pkg:freebsd/" + .[0] + "@" + .[1])
    }
  )
' /tmp/freebsd_raw.txt > /tmp/freebsd_components.json 2>/dev/null || echo "[]" > /tmp/freebsd_components.json

# Merge into CycloneDX SBOM
GENERATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq --slurpfile freebsd /tmp/freebsd_components.json \
  --arg image "$IMAGE_NAME" \
  --arg tag "$TAG" \
  --arg arch "$ARCH" \
  --arg version "$APP_VERSION" \
  --arg source "$SOURCE" \
  --arg generated "$GENERATED" \
  '
  .metadata.component.name = $image |
  .metadata.component.version = $version |
  .metadata.component.properties = [
    {name: "daemonless:tag", value: $tag},
    {name: "daemonless:arch", value: $arch},
    {name: "daemonless:source", value: $source},
    {name: "daemonless:generated", value: $generated}
  ] |
  .components = (.components + $freebsd[0]) |
  .metadata.tools = [{
    vendor: "daemonless",
    name: "sbom-generator",
    version: "1.0"
  }]
' /tmp/trivy-sbom.json > "$SBOM_FILE"

# Summary
FREEBSD_COUNT=$(jq 'length' /tmp/freebsd_components.json)
APP_COUNT=$(jq '.components | map(select(.purl | startswith("pkg:freebsd") | not)) | length' "$SBOM_FILE" 2>/dev/null || echo 0)
TOTAL_COUNT=$(jq '.components | length' "$SBOM_FILE")

echo "=== SBOM Complete ==="
echo "FreeBSD packages: $FREEBSD_COUNT"
echo "App packages: $APP_COUNT"
echo "Total: $TOTAL_COUNT"
echo "Output: $SBOM_FILE"

# Cleanup
rm -f /tmp/image-scan.tar /tmp/trivy-sbom.json /tmp/freebsd_raw.txt /tmp/freebsd_components.json
