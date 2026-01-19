#!/usr/bin/env python3
"""
Generate daemonless-versions.json by fetching service info from GitHub.

Uses GitHub API to discover repos and raw.githubusercontent.com to fetch
Containerfiles. No local cloning required.
"""

import datetime
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

try:
    import yaml
except ImportError:
    yaml = None

GITHUB_ORG = "daemonless"
GITHUB_API = "https://api.github.com"
RAW_GITHUB = "https://raw.githubusercontent.com"

# Repos to skip (not services)
SKIP_REPOS = {
    "daemonless",
    "daemonless-io",
    "ci-daemonless-io",
    "freebsd-ports",
    "base",
    "arr-base",
    "nginx-base",
    "cit",
}


def get_github_token():
    """Get GitHub token from environment or gh CLI."""
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        return token
    try:
        result = subprocess.run(
            ["gh", "auth", "token"],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    except Exception:
        return None


def fetch_url(url, accept=None):
    """Fetch URL content with optional GitHub authentication."""
    headers = {"User-Agent": "daemonless-versions/1.0"}

    if "api.github.com" in url or "raw.githubusercontent.com" in url:
        token = get_github_token()
        if token:
            headers["Authorization"] = f"token {token}"

    if accept:
        headers["Accept"] = accept

    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=30) as response:
            return response.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        if e.code == 403:
            print(f"Rate limited: {url}", file=sys.stderr)
        else:
            print(f"HTTP {e.code}: {url}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Error fetching {url}: {e}", file=sys.stderr)
        return None


def list_repos():
    """List all repos in the daemonless org via GitHub API."""
    repos = []
    page = 1
    per_page = 100

    while True:
        url = f"{GITHUB_API}/orgs/{GITHUB_ORG}/repos?per_page={per_page}&page={page}"
        content = fetch_url(url, accept="application/vnd.github.v3+json")
        if not content:
            break

        data = json.loads(content)
        if not data:
            break

        for repo in data:
            name = repo.get("name")
            if name and name not in SKIP_REPOS:
                repos.append(name)

        if len(data) < per_page:
            break
        page += 1

    return sorted(repos)


def fetch_containerfiles(repo):
    """Fetch both Containerfile and Containerfile.pkg from repo."""
    results = {}
    for filename in ["Containerfile", "Containerfile.pkg"]:
        url = f"{RAW_GITHUB}/{GITHUB_ORG}/{repo}/main/{filename}"
        content = fetch_url(url)
        if content:
            results[filename] = content
    return results


def parse_simple_yaml(content):
    """Simple YAML parser for config.yaml when PyYAML not available."""
    if not content:
        return None

    result = {}
    current_section = None
    current_subsection = None

    for line in content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        # Calculate indent level
        indent = len(line) - len(line.lstrip())

        # Parse key: value
        if ":" in stripped:
            key, _, value = stripped.partition(":")
            key = key.strip()
            value = value.strip()

            # Remove quotes from value
            if value.startswith('"') and value.endswith('"'):
                value = value[1:-1]
            elif value.startswith("'") and value.endswith("'"):
                value = value[1:-1]

            if indent == 0:
                # Top-level key
                if value:
                    result[key] = value
                else:
                    result[key] = {}
                    current_section = key
                    current_subsection = None
            elif indent == 2 and current_section:
                # Section-level key
                if isinstance(result.get(current_section), dict):
                    if value:
                        result[current_section][key] = value
                    else:
                        result[current_section][key] = {}
                        current_subsection = key
            elif indent == 4 and current_section and current_subsection:
                # Subsection-level key
                section = result.get(current_section)
                if isinstance(section, dict):
                    subsection = section.get(current_subsection)
                    if isinstance(subsection, dict):
                        subsection[key] = value

        # Handle list items (- value)
        elif stripped.startswith("- "):
            item = stripped[2:].strip()
            # Parse inline dict { key: val, ... }
            if item.startswith("{") and item.endswith("}"):
                item_dict = {}
                inner = item[1:-1]
                for part in inner.split(","):
                    if ":" in part:
                        k, _, v = part.partition(":")
                        k = k.strip()
                        v = v.strip().strip('"').strip("'")
                        item_dict[k] = v
                item = item_dict

            if current_section and current_subsection:
                section = result.get(current_section)
                if isinstance(section, dict):
                    subsection = section.get(current_subsection)
                    if not isinstance(subsection, list):
                        result[current_section][current_subsection] = []
                    result[current_section][current_subsection].append(item)

    return result


def get_config_yaml(repo):
    """Fetch and parse .daemonless/config.yaml from repo."""
    url = f"{RAW_GITHUB}/{GITHUB_ORG}/{repo}/main/.daemonless/config.yaml"
    content = fetch_url(url)
    if not content:
        return None

    if yaml:
        try:
            return yaml.safe_load(content)
        except Exception as e:
            print(f"  Error parsing config.yaml with PyYAML: {e}", file=sys.stderr)
            return None
    else:
        # Fall back to simple parser
        try:
            return parse_simple_yaml(content)
        except Exception as e:
            print(f"  Error parsing config.yaml: {e}", file=sys.stderr)
            return None


def resolve_vars(text, vars_dict):
    """Resolve ${VAR} references in text."""
    if not text:
        return text

    pattern = re.compile(r"\$\{([a-zA-Z0-9_]+)\}")

    for _ in range(5):
        match = pattern.search(text)
        if not match:
            break
        var_name = match.group(1)
        val = vars_dict.get(var_name, "")
        text = text.replace(f"${{{var_name}}}", val)

    return text


def parse_containerfile(content, repo_name=None):
    """Parse Containerfile content to extract ARGs and labels."""
    envs = {}
    labels = {}

    # Handle line continuations (backslash + newline)
    content_joined = re.sub(r"\\\s*\n\s*", " ", content)
    lines = content_joined.splitlines()

    # Parse ARGs
    for line in lines:
        line = line.strip()
        if line.startswith("ARG "):
            arg_content = line[4:].strip()
            if "=" in arg_content:
                key, val = arg_content.split("=", 1)
                key = key.strip()
                val = val.strip()

                # Handle quoting
                if val.startswith('"') and val.endswith('"'):
                    val = val[1:-1].replace(r"\"", '"')
                elif val.startswith("'") and val.endswith("'"):
                    val = val[1:-1]

                val = resolve_vars(val, envs)
                envs[key] = val

    # Use the joined content for label searching
    full_content = " ".join(lines)

    def find_label(name):
        """Find label value by name."""
        pattern = re.compile(
            rf'{re.escape(name)}\s*=\s*(?:"((?:[^"]|\\.)*)"|\'([^\']*)\'|([^\s]*))'
        )
        match = pattern.search(full_content)
        if match:
            if match.group(1) is not None:
                raw_val = match.group(1).replace(r"\"", '"')
            elif match.group(2) is not None:
                raw_val = match.group(2)
            else:
                raw_val = match.group(3)
            return resolve_vars(raw_val, envs)
        return None

    labels["upstream-url"] = find_label("io.daemonless.upstream-url")
    labels["upstream-jq"] = find_label("io.daemonless.upstream-jq")

    # Find pkg name from labels or ARGs
    # Only use PACKAGES if it matches repo name (not build dependencies like ca_root_nss)
    pkg_name = find_label("io.daemonless.pkg-name")
    if not pkg_name:
        pkg_name = envs.get("PKG_NAME")
    if not pkg_name and repo_name:
        # Check io.daemonless.packages label - only if matches repo name
        packages_label = find_label("io.daemonless.packages")
        if packages_label and packages_label == repo_name:
            pkg_name = packages_label
    if not pkg_name and repo_name:
        # Check ARG PACKAGES - only if matches repo name
        packages_arg = envs.get("PACKAGES")
        if packages_arg and packages_arg == repo_name:
            pkg_name = packages_arg

    labels["pkg-name"] = pkg_name

    return labels


def get_pkg_version(pkg_name, repo_type):
    """Query pkg version from FreeBSD repository."""
    if not pkg_name:
        return None

    repo_name = f"FreeBSD-{repo_type}"
    cmd = ["pkg", "rquery", "-r", repo_name, "%v", pkg_name]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except Exception as e:
        print(f"pkg query error for {pkg_name}: {e}", file=sys.stderr)

    return None


def get_upstream_version(upstream_url, upstream_jq):
    """Fetch upstream version using URL and jq filter."""
    if not upstream_url or not upstream_jq:
        return None

    content = fetch_url(upstream_url)
    if not content:
        return None

    try:
        result = subprocess.run(
            ["jq", "-r", upstream_jq],
            input=content,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0:
            val = result.stdout.strip()
            if val and val != "null":
                return val
    except Exception as e:
        print(f"jq error: {e}", file=sys.stderr)

    return None


def process_multi_version_service(repo, config):
    """Process a multi-version service using config.yaml variants."""
    versions_config = config.get("versions", {})
    variants = versions_config.get("variants", [])

    if not variants:
        return None

    result = {
        "type": "multi-version",
        "variants": {},
    }

    # Find default variant
    default_variant = None
    for variant in variants:
        if variant.get("default"):
            default_variant = variant.get("id")
            break

    if default_variant:
        result["default"] = default_variant

    # Process each variant
    for variant in variants:
        variant_id = variant.get("id")
        if not variant_id:
            continue

        pkg_name = variant.get("pkg_name")
        if not pkg_name:
            continue

        # Determine which pkg repo to query based on variant id
        # Variants ending in -pkg-latest use "latest" repo, others use "quarterly"
        if variant_id.endswith("-pkg-latest"):
            # This is a pkg-latest variant
            l_ver = get_pkg_version(pkg_name, "latest")
            if l_ver:
                result["variants"][variant_id] = {"pkg-latest": l_ver}
        else:
            # This is a quarterly (pkg) variant
            q_ver = get_pkg_version(pkg_name, "quarterly")
            if q_ver:
                result["variants"][variant_id] = {"pkg": q_ver}

    # Consolidate: group by major version
    # e.g., "14" and "14-pkg-latest" -> "14": {"pkg": x, "pkg-latest": y}
    consolidated = {}
    for variant_id, versions in result["variants"].items():
        # Extract base version (e.g., "14" from "14-pkg-latest")
        base_version = variant_id.replace("-pkg-latest", "")

        if base_version not in consolidated:
            consolidated[base_version] = {}

        consolidated[base_version].update(versions)

    if consolidated:
        result["variants"] = consolidated

    if not result["variants"]:
        return None

    return result


def process_service(repo):
    """Process a single service repo and return version info."""
    print(f"Processing {repo}...", file=sys.stderr)

    # First check for config.yaml with versions section
    config = get_config_yaml(repo)
    if config and "versions" in config:
        versions_config = config["versions"]

        # Check if multi-version service
        if versions_config.get("type") == "multi-version":
            print(f"  Multi-version service detected", file=sys.stderr)
            return process_multi_version_service(repo, config)

        # Simple config with just pkg_name override
        pkg_name_override = versions_config.get("pkg_name")
        if pkg_name_override:
            print(f"  Using pkg_name from config: {pkg_name_override}", file=sys.stderr)

    files = fetch_containerfiles(repo)
    if not files:
        print(f"  No Containerfile found", file=sys.stderr)
        return None

    # Parse both files and merge labels
    pkg_name = None
    upstream_url = None
    upstream_jq = None

    # Check Containerfile first (for upstream info)
    if "Containerfile" in files:
        labels = parse_containerfile(files["Containerfile"], repo)
        upstream_url = labels.get("upstream-url")
        upstream_jq = labels.get("upstream-jq")
        pkg_name = labels.get("pkg-name")

    # Check Containerfile.pkg (for pkg info) - this takes priority for pkg-name
    if "Containerfile.pkg" in files:
        pkg_labels = parse_containerfile(files["Containerfile.pkg"], repo)
        if pkg_labels.get("pkg-name"):
            pkg_name = pkg_labels.get("pkg-name")
        # Also grab upstream info if not found in Containerfile
        if not upstream_url:
            upstream_url = pkg_labels.get("upstream-url")
            upstream_jq = pkg_labels.get("upstream-jq")

    # Override pkg_name from config.yaml if specified
    if config and "versions" in config:
        pkg_name_override = config["versions"].get("pkg_name")
        if pkg_name_override:
            pkg_name = pkg_name_override

    result = {}

    # Get pkg versions
    if pkg_name:
        q_ver = get_pkg_version(pkg_name, "quarterly")
        l_ver = get_pkg_version(pkg_name, "latest")

        if q_ver:
            result["pkg"] = q_ver
        if l_ver:
            result["pkg-latest"] = l_ver

    # Get upstream version
    if upstream_url and upstream_jq:
        u_ver = get_upstream_version(upstream_url, upstream_jq)
        if u_ver:
            result["upstream"] = u_ver

    if not result:
        print(f"  No versions found", file=sys.stderr)
        return None

    return result


def main():
    print("Fetching repo list from GitHub...", file=sys.stderr)
    repos = list_repos()
    print(f"Found {len(repos)} repos", file=sys.stderr)

    services = {}
    for repo in repos:
        result = process_service(repo)
        if result:
            services[repo] = result

    output = {
        "last_check": datetime.datetime.now(datetime.timezone.utc)
        .isoformat()
        .replace("+00:00", "Z"),
        "services": services,
    }

    print(json.dumps(output, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
