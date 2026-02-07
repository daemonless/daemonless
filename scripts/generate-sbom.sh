#!/bin/sh
#
# Generate SBOM for FreeBSD container images
#
# Version: 1.1.0
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

SBOM_VERSION="1.3.0"

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

# Mount image filesystem via buildah (avoids multi-GB tar export)
BUILDAH="buildah"
[ "$PODMAN" = "doas podman" ] && BUILDAH="doas buildah"
echo "Mounting image filesystem..."
SBOM_CTR=$($BUILDAH from "$IMAGE")
SBOM_MNT=$($BUILDAH mount "$SBOM_CTR")

# Run Trivy to detect app packages
echo "Running Trivy scan..."
trivy rootfs "$SBOM_MNT" --format json --scanners vuln \
  --output /tmp/trivy.json 2>&1 || echo '{}' > /tmp/trivy.json

# Unmount
$BUILDAH umount "$SBOM_CTR"
$BUILDAH rm "$SBOM_CTR"

# Extract FreeBSD packages
echo "Extracting FreeBSD packages..."
$PODMAN run --rm --entrypoint sh "$IMAGE" -c 'pkg query "%n %v"' 2>/dev/null | \
  tr -cd '[:print:]\n' | \
  jq -R 'split(" ") | {name: .[0], version: .[1]}' | \
  jq -s '.' > /tmp/freebsd_pkgs.json 2>/dev/null || echo "[]" > /tmp/freebsd_pkgs.json

# Extract packages by type from Trivy output
jq '{
  dotnet: [.Results[]? | select(.Type == "dotnet-core") | .Packages[]? | {name: .Name, version: .Version}] | unique_by(.name),
  go: [.Results[]? | select(.Type == "gobinary" or .Type == "gomod") | .Packages[]? | {name: .Name, version: .Version}] | unique_by(.name),
  java: [.Results[]? | select(.Type == "jar" or .Type == "pom") | .Packages[]? | {name: .Name, version: .Version}] | unique_by(.name),
  node: [.Results[]? | select(.Type == "node-pkg") | .Packages[]? | {name: .Name, version: .Version}] | unique_by(.name),
  php: [.Results[]? | select(.Type == "composer") | .Packages[]? | {name: .Name, version: .Version}] | unique_by(.name),
  python: [.Results[]? | select(.Type == "python-pkg") | .Packages[]? | {name: .Name, version: .Version}] | unique_by(.name),
  ruby: [.Results[]? | select(.Type == "bundler" or .Type == "gemspec") | .Packages[]? | {name: .Name, version: .Version}] | unique_by(.name),
  rust: [.Results[]? | select(.Type == "rustbinary" or .Type == "cargo") | .Packages[]? | {name: .Name, version: .Version}] | unique_by(.name)
}' /tmp/trivy.json > /tmp/trivy_pkgs.json 2>/dev/null || echo '{"dotnet":[],"go":[],"java":[],"node":[],"php":[],"python":[],"ruby":[],"rust":[]}' > /tmp/trivy_pkgs.json

# Build SBOM in simple format
GENERATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n \
  --arg image "$IMAGE_NAME" \
  --arg tag "$TAG" \
  --arg arch "$ARCH" \
  --arg version "$APP_VERSION" \
  --arg source "$SOURCE" \
  --arg generated "$GENERATED" \
  --slurpfile freebsd /tmp/freebsd_pkgs.json \
  --slurpfile trivy /tmp/trivy_pkgs.json \
  '{
    image: $image,
    tag: $tag,
    arch: $arch,
    app_version: $version,
    source: $source,
    generated: $generated,
    packages: {
      freebsd: $freebsd[0],
      dotnet: $trivy[0].dotnet,
      go: $trivy[0].go,
      java: $trivy[0].java,
      node: $trivy[0].node,
      php: $trivy[0].php,
      python: $trivy[0].python,
      ruby: $trivy[0].ruby,
      rust: $trivy[0].rust
    },
    summary: {
      freebsd: ($freebsd[0] | length),
      dotnet: ($trivy[0].dotnet | length),
      go: ($trivy[0].go | length),
      java: ($trivy[0].java | length),
      node: ($trivy[0].node | length),
      php: ($trivy[0].php | length),
      python: ($trivy[0].python | length),
      ruby: ($trivy[0].ruby | length),
      rust: ($trivy[0].rust | length),
      total: (($freebsd[0] | length) + ($trivy[0].dotnet | length) + ($trivy[0].go | length) + ($trivy[0].java | length) + ($trivy[0].node | length) + ($trivy[0].php | length) + ($trivy[0].python | length) + ($trivy[0].ruby | length) + ($trivy[0].rust | length))
    }
  }' > "$SBOM_FILE"

# Summary
echo "=== SBOM Complete ==="
jq -c '.summary' "$SBOM_FILE"
echo "Output: $SBOM_FILE"

# Cleanup
rm -f /tmp/trivy.json /tmp/freebsd_pkgs.json /tmp/trivy_pkgs.json
