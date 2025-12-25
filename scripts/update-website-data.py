#!/usr/bin/env python3
import os
import json
import re
from pathlib import Path

# Paths
ROOT_DIR = Path("/var/home/ahze/src/daemonless")
DAEMONLESS_DIR = ROOT_DIR / "daemonless"
OUTPUT_FILE = ROOT_DIR / "daemonless-io/dependencies.json"

# Schema structure
data = {
    "description": "Dependency graph for daemonless container images. Generated from Containerfile labels.",
    "base_images": {},
    "images": {},
    "upstream_sources": {}
}

def parse_containerfile(path):
    info = {
        "parent": None,
        "labels": {},
        "packages": [],
        "pkgs_arg": None
    }
    
    with open(path, "r") as f:
        content = f.read()
        
    # Find FROM
    from_match = re.search(r"^FROM\s+ghcr\.io/daemonless/([^:]+)", content, re.MULTILINE)
    if from_match:
        info["parent"] = from_match.group(1)
        
    # Find ARG PACKAGES
    arg_match = re.search(r'^ARG PACKAGES="([^"]+)"', content, re.MULTILINE)
    if arg_match:
        info["pkgs_arg"] = arg_match.group(1).split(" ")
        
    # Find LABELS
    # This is a simple regex, might need to be more robust for multi-line labels but 
    # for now we assume labels are well formed or we catch the specific ones we need.
    # Actually, let's look for specific keys we inserted.
    
    label_patterns = {
        "io.daemonless.category": r'io\.daemonless\.category="([^"]+)"',
        "io.daemonless.packages": r'io\.daemonless\.packages="([^"]+)"',
        "io.daemonless.upstream-mode": r'io\.daemonless\.upstream-mode="([^"]+)"',
        "io.daemonless.upstream-url": r'io\.daemonless\.upstream-url="([^"]+)"',
        "io.daemonless.upstream-repo": r'io\.daemonless\.upstream-repo="([^"]+)"',
        "io.daemonless.upstream-package": r'io\.daemonless\.upstream-package="([^"]+)"',
        "io.daemonless.upstream-branch": r'io\.daemonless\.upstream-branch="([^"]+)"',
        "io.daemonless.wip": r'io\.daemonless\.wip="([^"]+)"'
    }
    
    for key, pattern in label_patterns.items():
        match = re.search(pattern, content)
        if match:
            val = match.group(1)
            # If it's the packages label and we explicitly used ${PACKAGES}, resolve it
            if key == "io.daemonless.packages" and val == "${PACKAGES}" and info["pkgs_arg"]:
                info["labels"][key] = info["pkgs_arg"]
            elif key == "io.daemonless.packages" and "," in val:
                 info["labels"][key] = val.split(",")
            else:
                info["labels"][key] = val
                
    return info

def main():
    # Helper to track children
    parent_map = {} # parent -> [children]
    
    # 1. Scan directories
    for child in ROOT_DIR.iterdir():
        if not child.is_dir() or child.name in [".git", "daemonless", "daemonless-io", "scripts"]:
            continue
            
        containerfile = child / "Containerfile"
        # Special case for base image which is in base/15/Containerfile
        if child.name == "base":
            containerfile = child / "15/Containerfile"
            
        if not containerfile.exists():
            continue
            
        info = parse_containerfile(containerfile)
        name = child.name
        labels = info["labels"]
        
        # Populate Base Images
        if name in ["base", "arr-base", "nginx-base"]:
            base_entry = {
                "packages": labels.get("io.daemonless.packages", []),
                "children": []
            }
            if info["parent"] and info["parent"] != name: # Avoid self-ref if any
                base_entry["parent"] = info["parent"]
            data["base_images"][name] = base_entry
        else:
            # Populate Images
            image_entry = {
                "parent": info["parent"],
                "category": labels.get("io.daemonless.category", "Uncategorized"),
                "tags": {}
            }
            
            # Construct Tags
            mode = labels.get("io.daemonless.upstream-mode", "source")
            
            # Latest Tag
            latest_tag = {}
            if mode == "pkg":
                 latest_tag = { "type": "pkg", "repo": "latest", "package": name } # Assumption: package name = image name usually
                 if "io.daemonless.upstream-package" in labels:
                     latest_tag["package"] = labels["io.daemonless.upstream-package"]
            else:
                latest_tag = { "type": "source", "upstream": name }
                if labels.get("io.daemonless.wip") == "true":
                    latest_tag["wip"] = True
            
            image_entry["tags"]["latest"] = latest_tag
            
            # Standard PKG tags (valid for almost all, except maybe some source-only ones?)
            # Validating against previous JSON, most have these.
            image_entry["tags"]["pkg"] = { "type": "pkg", "repo": "quarterly", "package": name }
            image_entry["tags"]["pkg-latest"] = { "type": "pkg", "repo": "latest", "package": name }
            
            data["images"][name] = image_entry
            
            # Populate Upstream Sources
            upstream_entry = {}
            if mode == "servarr":
                upstream_entry = { "type": "servarr", "url": labels.get("io.daemonless.upstream-url") }
            elif mode == "sonarr": # Specific type for legacy reasons or just treat as servarr? JSON had "sonarr".
                 upstream_entry = { "type": "sonarr", "url": labels.get("io.daemonless.upstream-url") }
            elif mode == "github":
                upstream_entry = { "type": "github", "repo": labels.get("io.daemonless.upstream-repo") }
            elif mode == "github_commits":
                upstream_entry = { 
                    "type": "github_commits", 
                    "repo": labels.get("io.daemonless.upstream-repo"),
                    "branch": labels.get("io.daemonless.upstream-branch")
                }
            elif mode == "npm":
                 upstream_entry = { "type": "npm", "package": labels.get("io.daemonless.upstream-package") }
            elif mode == "ubiquiti":
                 upstream_entry = { "type": "ubiquiti", "url": "https://fw-update.ubnt.com/api/firmware-latest" } # Hardcoded to simple type in JSON usually
            
            if upstream_entry:
                data["upstream_sources"][name] = upstream_entry

        # Track parent/child for base images
        if info["parent"]:
             if info["parent"] not in parent_map:
                 parent_map[info["parent"]] = []
             parent_map[info["parent"]].append(name)

    # Fill in children for base images
    for base_name, entry in data["base_images"].items():
        if base_name in parent_map:
            entry["children"] = sorted(parent_map[base_name])

    # Write output
    with open(OUTPUT_FILE, "w") as f:
        json.dump(data, f, indent=2)
        print(f"Generated {OUTPUT_FILE}")

if __name__ == "__main__":
    main()
