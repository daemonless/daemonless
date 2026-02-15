#!/usr/bin/env python3
"""
Compare daemonless-versions.json against deployed ghcr.io tags.
Shows which images are out of date and need rebuilding.
"""

import argparse
import json
import subprocess
import sys
import re
from pathlib import Path

VERSIONS_FILE = Path(__file__).parent.parent / "daemonless-versions.json"
ORG = "daemonless"

def get_deployed_versions(package: str, variant: str = None) -> dict:
    """Get currently deployed versions from ghcr.io tags.

    If variant is specified (e.g., "14" for postgres), only look for tags
    matching that variant (14-pkg, 14-pkg-latest, 14.x.x).
    """
    try:
        # Get all version info with tags grouped
        result = subprocess.run(
            ["gh", "api", f"/orgs/{ORG}/packages/container/{package}/versions",
             "--jq", '.[] | {tags: .metadata.container.tags}'],
            capture_output=True, text=True, check=True
        )
        lines = result.stdout.strip().split("\n") if result.stdout.strip() else []
    except subprocess.CalledProcessError:
        return {}

    deployed = {}
    latest_is_pkg = False  # Track if 'latest' is aliased to a pkg build

    for line in lines:
        if not line.strip():
            continue
        try:
            data = json.loads(line)
            tags = data.get("tags", [])
        except json.JSONDecodeError:
            continue

        # Check if this version has the 'latest' alias alongside a pkg tag
        has_latest = "latest" in tags

        if variant:
            # Multi-version mode: look for variant-specific tags
            variant_pkg = f"{variant}-pkg"
            variant_pkg_latest = f"{variant}-pkg-latest"

            for tag in tags:
                # Version tags from push.py: {version}-{variant_tag}
                # e.g., "14.20_1-14-pkg-latest", "14.20_1-14", "11.4.9-11.4-pkg-latest"
                suffix_pkg_latest = f"-{variant}-pkg-latest"
                suffix_pkg = f"-{variant}-pkg"
                suffix_variant = f"-{variant}"

                if tag.endswith(suffix_pkg_latest) and tag.startswith(f"{variant}."):
                    version = tag[: -len(suffix_pkg_latest)]
                    if "pkg-latest" not in deployed:
                        deployed["pkg-latest"] = version
                elif tag.endswith(suffix_pkg) and tag.startswith(f"{variant}."):
                    version = tag[: -len(suffix_pkg)]
                    if "pkg" not in deployed:
                        deployed["pkg"] = version
                # Legacy: "14.20-pkg-latest" (without variant in suffix)
                elif tag.endswith("-pkg-latest") and tag.startswith(f"{variant}."):
                    version = tag.replace("-pkg-latest", "")
                    if "pkg-latest" not in deployed:
                        deployed["pkg-latest"] = version
                elif tag.endswith("-pkg") and tag.startswith(f"{variant}."):
                    version = tag.replace("-pkg", "")
                    if "pkg" not in deployed:
                        deployed["pkg"] = version
                # Plain version tag: "14.20_1-14" or "14.20"
                elif tag.endswith(suffix_variant) and tag.startswith(f"{variant}."):
                    version = tag[: -len(suffix_variant)]
                    if "pkg" not in deployed:
                        deployed["pkg"] = version
                elif tag.startswith(f"{variant}.") and "-" not in tag:
                    if "pkg" not in deployed:
                        deployed["pkg"] = tag
                    if "pkg-latest" not in deployed:
                        deployed["pkg-latest"] = tag
        else:
            # Standard single-version mode
            for tag in tags:
                if tag in ("latest", "pkg", "pkg-latest"):
                    continue
                if tag.endswith("-pkg-latest"):
                    # Only set if not already set (newest first from API)
                    if "pkg-latest" not in deployed:
                        deployed["pkg-latest"] = tag.replace("-pkg-latest", "")
                    if has_latest:
                        latest_is_pkg = True
                elif tag.endswith("-pkg"):
                    if "pkg" not in deployed:
                        deployed["pkg"] = tag.replace("-pkg", "")
                    if has_latest:
                        latest_is_pkg = True
                elif not "-" in tag or re.match(r"^\d+\.\d+", tag):
                    # Version tag without suffix = latest/upstream
                    if "latest" not in deployed and not latest_is_pkg:
                        deployed["latest"] = tag

            # If latest is just an alias to pkg, don't track it separately
            if latest_is_pkg:
                deployed.pop("latest", None)

    return deployed


def normalize_version(v: str) -> str:
    """Normalize version for comparison (strip 'v' prefix, handle epoch commas, etc)."""
    if not v:
        return ""
    v = v.lstrip("v")
    # Convert commas to underscores (OCI tags can't have commas)
    v = v.replace(",", "_")
    return v


def versions_match(available: str, deployed: str) -> bool:
    """Check if versions match (with normalization)."""
    return normalize_version(available) == normalize_version(deployed)


def output_text(outdated, current, errors):
    """Output as plain text."""
    if outdated:
        print("=" * 60)
        print("OUTDATED IMAGES")
        print("=" * 60)
        for item in outdated:
            print(f"\n{item['name']}:")
            for update in item["updates"]:
                print(f"  {update['tag']}: {update['deployed']} → {update['available']}")

    if errors:
        print("\n" + "=" * 60)
        print("ERRORS")
        print("=" * 60)
        for item in errors:
            print(f"  {item['name']}: {item['error']}")

    print("\n" + "=" * 60)
    print(f"SUMMARY: {len(current)} current, {len(outdated)} outdated, {len(errors)} errors")
    print("=" * 60)


def output_json(outdated, current, errors):
    """Output as JSON."""
    result = {
        "outdated": outdated,
        "current": current,
        "errors": errors,
        "summary": {
            "current_count": len(current),
            "outdated_count": len(outdated),
            "error_count": len(errors)
        }
    }
    print(json.dumps(result, indent=2))


def output_markdown(outdated, current, errors, all_services=None, deployed_info=None):
    """Output as Markdown table."""
    print("# Daemonless Version Status\n")

    # Build a combined view of all services
    if all_services and deployed_info:
        print("| Status | Image | Tag | Version |")
        print("|:------:|-------|-----|---------|")

        # Create lookup for outdated items
        outdated_lookup = {}
        for item in outdated:
            for update in item["updates"]:
                key = (item["name"], update["tag"])
                outdated_lookup[key] = update

        # Print all services sorted by name
        for name, versions in sorted(all_services.items()):
            deployed = deployed_info.get(name, {})
            repo = versions.get("_base_name", name)
            actions_url = f"https://github.com/daemonless/{repo}/actions/workflows/build.yaml"

            # Check each tag type - only show if actually deployed
            for tag in ["pkg", "pkg-latest", "latest"]:
                key = (name, tag)
                if key in outdated_lookup:
                    update = outdated_lookup[key]
                    available = update['available'].lstrip('v')
                    print(f"| :material-close-circle:{{ .outdated }} | [{name}]({actions_url}) | {tag} | {update['deployed']} → **{available}** |")
                elif tag in deployed:
                    # Current - show deployed version
                    print(f"| :material-check-circle:{{ .current }} | [{name}]({actions_url}) | {tag} | {deployed[tag]} |")
        print()

    if errors:
        print("## Errors\n")
        for item in errors:
            print(f"- :material-alert-circle: **{item['name']}**: {item['error']}")
        print()

    print(f"## Summary\n")
    print(f"- :material-check-circle:{{ .current }} Current: {len(current)}")
    print(f"- :material-close-circle:{{ .outdated }} Outdated: {len(outdated)}")
    if errors:
        print(f"- :material-alert-circle: Errors: {len(errors)}")


def main():
    parser = argparse.ArgumentParser(description="Compare versions against ghcr.io")
    parser.add_argument("--format", "-f", choices=["text", "json", "markdown"], default="text",
                        help="Output format (default: text)")
    parser.add_argument("--quiet", "-q", action="store_true",
                        help="Suppress progress output")
    args = parser.parse_args()

    with open(VERSIONS_FILE) as f:
        data = json.load(f)

    services = data.get("services", {})

    outdated = []
    current = []
    errors = []
    deployed_info = {}  # Track all deployed versions for markdown output

    if not args.quiet and args.format == "text":
        print(f"Checking {len(services)} services against ghcr.io...\n", file=sys.stderr)

    # Expand multi-version services into separate entries
    expanded_services = {}
    for name, versions in services.items():
        if versions.get("type") == "multi-version":
            # Expand variants into separate entries (e.g., postgres-14, postgres-17)
            for variant_id, variant_versions in versions.get("variants", {}).items():
                expanded_name = f"{name}-{variant_id}"
                expanded_services[expanded_name] = {
                    "_base_name": name,
                    "_variant": variant_id,
                    **variant_versions
                }
        else:
            expanded_services[name] = versions

    for name, versions in sorted(expanded_services.items()):
        base_name = versions.get("_base_name", name)
        variant = versions.get("_variant")

        deployed = get_deployed_versions(base_name, variant)
        deployed_info[name] = deployed

        if not deployed:
            errors.append({"name": name, "error": "No tags found in ghcr.io"})
            continue

        service_outdated = []

        # Check pkg
        if "pkg" in versions and "pkg" in deployed:
            if not versions_match(versions["pkg"], deployed["pkg"]):
                service_outdated.append({
                    "tag": "pkg",
                    "available": versions["pkg"],
                    "deployed": deployed["pkg"]
                })

        # Check pkg-latest
        if "pkg-latest" in versions and "pkg-latest" in deployed:
            if not versions_match(versions["pkg-latest"], deployed["pkg-latest"]):
                service_outdated.append({
                    "tag": "pkg-latest",
                    "available": versions["pkg-latest"],
                    "deployed": deployed["pkg-latest"]
                })

        # Check upstream (latest tag)
        if "upstream" in versions and "latest" in deployed:
            if not versions_match(versions["upstream"], deployed["latest"]):
                service_outdated.append({
                    "tag": "latest",
                    "available": versions["upstream"],
                    "deployed": deployed["latest"]
                })

        if service_outdated:
            outdated.append({"name": name, "updates": service_outdated})
        else:
            current.append(name)

    # Output results
    if args.format == "json":
        output_json(outdated, current, errors)
    elif args.format == "markdown":
        output_markdown(outdated, current, errors, expanded_services, deployed_info)
    else:
        output_text(outdated, current, errors)

    # Exit with error if anything is outdated
    sys.exit(1 if outdated else 0)


if __name__ == "__main__":
    main()
