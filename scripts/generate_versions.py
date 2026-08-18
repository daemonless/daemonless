#!/usr/bin/env python3
"""
Generate daemonless-versions.json by fetching service info from GitHub.

Uses GitHub API to discover repos and raw.githubusercontent.com to fetch
Containerfiles. No local cloning required.

pkg versions are recorded PER ARCH (schema_version 2): `pkg` and `pkg-latest`
are objects keyed by arch ({"amd64": "...", "aarch64": "..."}) because FreeBSD's
aarch64 pkg repo routinely lags amd64 on PORTREVISION bumps. `upstream` (the
binary release version) is arch-agnostic and stays a scalar. The comparator
compares each arch against the same arch, so cross-arch lag no longer
false-flags an image as outdated.
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

# pkg ABI is keyed by major only (FreeBSD:<major>:<arch>); major comes from
# each image's BASE_VERSION. DEFAULT_MAJOR is the fallback for non-numeric
# BASE_VERSION (e.g. "latest").
DEFAULT_MAJOR = "15"

# FreeBSD architectures we publish and therefore track upstream versions for.
# pkg versions are recorded PER ARCH: FreeBSD's aarch64 pkg builder routinely
# lags amd64 on PORTREVISION (`_N`) bumps, so a single amd64-only number would
# false-flag the arm64 image as outdated forever. The comparator compares each
# arch against the same arch, and only the arches actually published by an image
# (from its manifest list) are compared.
ARCHES = ("amd64", "aarch64")
DEFAULT_ARCH = "amd64"

# pkg branch directory names (also the repo_type values used throughout).
PKG_BRANCHES = ("quarterly", "latest")


def pkg_repo_url(major, branch, arch=DEFAULT_ARCH):
    """URL of a FreeBSD pkg repository for a given major/branch/arch."""
    return f"http://pkg.FreeBSD.org/FreeBSD:{major}:{arch}/{branch}"


def extract_freebsd_major(base_version):
    """Derive the FreeBSD pkg major version from a BASE_VERSION string.

    BASE_VERSION is the base image tag an image builds FROM, e.g. "15", "15.1",
    "15-latest", "15.1-pkg-latest", "15-quarterly". Only the leading integer
    matters for the pkg ABI. Returns it as a string, or DEFAULT_MAJOR when none
    can be parsed (e.g. "latest").
    """
    if base_version:
        m = re.match(r"\s*(\d+)", str(base_version))
        if m:
            return m.group(1)
        print(
            f"  Non-numeric BASE_VERSION={base_version!r}; "
            f"defaulting FreeBSD major to {DEFAULT_MAJOR}",
            file=sys.stderr,
        )
    return DEFAULT_MAJOR


# Cache for pkg indices, keyed by (major, repo_type) (loaded lazily)
_pkg_index_cache = {}

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
    "booklore",
    "overseerr",
    ".github",
    "dbuild",
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
    labels["base-version"] = envs.get("BASE_VERSION")

    return labels


def load_pkg_index(repo_type, major, arch=DEFAULT_ARCH):
    """Load and cache the package index from FreeBSD pkg server."""
    cache_key = (major, repo_type, arch)
    if cache_key in _pkg_index_cache:
        return _pkg_index_cache[cache_key]

    if repo_type not in PKG_BRANCHES:
        print(f"Unknown repo type: {repo_type}", file=sys.stderr)
        return {}

    # Fetch packagesite.pkg and extract using command-line tools
    # FreeBSD uses zstd-compressed tar archives
    pkg_url = f"{pkg_repo_url(major, repo_type, arch)}/packagesite.pkg"
    print(f"  Fetching pkg index from {pkg_url}...", file=sys.stderr)

    yaml_content = None

    # Use fetch + zstd + tar pipeline (most reliable on FreeBSD)
    try:
        result = subprocess.run(
            f'fetch -qo - "{pkg_url}" | zstd -d | tar -xOf - packagesite.yaml',
            shell=True,
            capture_output=True,
            text=True,
            timeout=300,
        )
        if result.returncode == 0 and result.stdout:
            yaml_content = result.stdout
    except Exception as e:
        print(f"  Error with zstd extraction: {e}", file=sys.stderr)

    # Fallback: try xz
    if not yaml_content:
        try:
            result = subprocess.run(
                f'fetch -qo - "{pkg_url}" | xz -d | tar -xOf - packagesite.yaml',
                shell=True,
                capture_output=True,
                text=True,
                timeout=300,
            )
            if result.returncode == 0 and result.stdout:
                yaml_content = result.stdout
        except Exception:
            pass

    if not yaml_content:
        print(f"  Could not extract packagesite.yaml from {repo_type}", file=sys.stderr)
        _pkg_index_cache[cache_key] = {}
        return {}

    # Parse the YAML (actually JSON lines format)
    index = {}
    for line in yaml_content.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            pkg_info = json.loads(line)
            name = pkg_info.get("name")
            version = pkg_info.get("version")
            if name and version:
                index[name] = version
        except json.JSONDecodeError:
            continue

    print(
        f"  Loaded {len(index)} packages from FreeBSD:{major}:{arch} {repo_type}",
        file=sys.stderr,
    )
    _pkg_index_cache[cache_key] = index
    return index


def get_pkg_version(pkg_name, repo_type, major, arch=DEFAULT_ARCH):
    """Query pkg version from a single FreeBSD repository (one arch)."""
    if not pkg_name:
        return None

    index = load_pkg_index(repo_type, major, arch)
    return index.get(pkg_name)


def get_pkg_versions_per_arch(pkg_name, repo_type, major):
    """Return {arch: version} for a pkg across all tracked ARCHES.

    Arches where the package is absent (e.g. an arch FreeBSD hasn't built yet)
    are omitted rather than recorded as null, so the comparator simply has no
    target to compare that arch against.
    """
    if not pkg_name:
        return {}
    out = {}
    for arch in ARCHES:
        ver = get_pkg_version(pkg_name, repo_type, major, arch)
        if ver:
            out[arch] = ver
    return out


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


def parse_variant_tag(variant_id, pkg_name):
    """Parse variant tag into (major_version, build_type).

    Handles both postgres-style numeric tags ("14", "14-pkg-latest") and
    samba-style alias tags ("pkg", "pkg-latest", "422-pkg", "422-pkg-krb").
    Returns (major_version_str, build_type_str).
    """
    # Try numeric prefix: "422-pkg-krb" -> ("422", "pkg-krb")
    m = re.match(r'^([\d.]+)(?:-(.+))?$', variant_id)
    if m:
        major = m.group(1)
        build_type = m.group(2) or "pkg"
        return major, build_type

    # Try word prefix before a known build-type suffix: "lts-pkg" -> ("lts", "pkg")
    m = re.match(r'^(.+?)-(pkg(?:-.+)?)$', variant_id)
    if m:
        return m.group(1), m.group(2)

    # No prefix (e.g. "pkg", "pkg-latest") — extract major from pkg_name
    pkg_major = re.search(r'(\d+)', pkg_name)
    major = pkg_major.group(1) if pkg_major else pkg_name

    if variant_id == "pkg-latest" or variant_id.endswith("-pkg-latest"):
        return major, "pkg-latest"
    return major, "pkg"


def process_multi_version_service(repo, config):
    """Process a multi-version service using build.variants with pkg_name."""
    build_config = config.get("build", {})
    variants = build_config.get("variants", [])

    if not variants:
        return None

    # Default BASE_VERSION for variants that don't set their own.
    default_base = build_config.get("args", {}).get("BASE_VERSION")

    # Check if any variant has pkg_name (required for version tracking)
    has_pkg_name = any(v.get("pkg_name") for v in variants)
    if not has_pkg_name:
        return None

    result = {
        "type": "multi-version",
        "variants": {},
    }

    # Find default variant (use its parsed major version as the default key)
    default_variant = None
    for variant in variants:
        if variant.get("default"):
            tag = variant.get("tag") or variant.get("id", "")
            pkg_name = variant.get("pkg_name", "")
            major, _ = parse_variant_tag(tag, pkg_name)
            default_variant = major
            break

    if default_variant:
        result["default"] = default_variant

    # Process each variant and consolidate by major version
    consolidated = {}
    for variant in variants:
        variant_id = variant.get("tag") or variant.get("id")
        if not variant_id:
            continue

        pkg_name = variant.get("pkg_name")
        if not pkg_name:
            continue

        major, build_type = parse_variant_tag(variant_id, pkg_name)

        # FreeBSD major comes ONLY from BASE_VERSION, never the app-version tag:
        # postgres tag "16" builds on BASE_VERSION "15-quarterly", and
        # postgresql16-server lives in the FreeBSD:15 repo.
        variant_base = variant.get("args", {}).get("BASE_VERSION") or default_base
        freebsd_major = extract_freebsd_major(variant_base)

        repo_type = "latest" if build_type == "pkg-latest" else "quarterly"
        vers = get_pkg_versions_per_arch(pkg_name, repo_type, freebsd_major)
        if vers:
            if major not in consolidated:
                consolidated[major] = {}
            consolidated[major][build_type] = vers

    result["variants"] = consolidated

    if not result["variants"]:
        return None

    return result


def process_service(repo):
    """Process a single service repo and return version info."""
    print(f"Processing {repo}...", file=sys.stderr)

    # First check for config.yaml with build.variants section
    config = get_config_yaml(repo)
    if config:
        build_config = config.get("build", {})

        # Check if multi-version service (build.variants with pkg_name)
        has_build_variants_with_pkg = any(
            v.get("pkg_name") for v in build_config.get("variants", [])
        )

        if has_build_variants_with_pkg:
            print(f"  Multi-version service detected", file=sys.stderr)
            return process_multi_version_service(repo, config)

        # Simple config with just pkg_name override
        pkg_name_override = build_config.get("pkg_name")
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
    cf_base_version = None
    pkg_base_version = None

    # Check Containerfile first (for upstream info)
    if "Containerfile" in files:
        labels = parse_containerfile(files["Containerfile"], repo)
        upstream_url = labels.get("upstream-url")
        upstream_jq = labels.get("upstream-jq")
        pkg_name = labels.get("pkg-name")
        cf_base_version = labels.get("base-version")

    # Check Containerfile.pkg (for pkg info) - this takes priority for pkg-name
    if "Containerfile.pkg" in files:
        pkg_labels = parse_containerfile(files["Containerfile.pkg"], repo)
        if pkg_labels.get("pkg-name"):
            pkg_name = pkg_labels.get("pkg-name")
        pkg_base_version = pkg_labels.get("base-version")
        # Also grab upstream info if not found in Containerfile
        if not upstream_url:
            upstream_url = pkg_labels.get("upstream-url")
            upstream_jq = pkg_labels.get("upstream-jq")

    # Override pkg_name from config.yaml if specified
    if config and "build" in config:
        pkg_name_override = config["build"].get("pkg_name")
        if pkg_name_override:
            pkg_name = pkg_name_override

    # FreeBSD major for pkg queries: config build.args override wins (either
    # top-level build.args.BASE_VERSION, or -- the normal dbuild shape --
    # nested in the default/first variant's own args), then the pkg
    # Containerfile's ARG (authoritative for pkg builds), then the plain
    # Containerfile's ARG.
    config_base_version = None
    if config:
        build_config_ = config.get("build", {})
        config_base_version = build_config_.get("args", {}).get("BASE_VERSION")
        if not config_base_version:
            variants_ = build_config_.get("variants", [])
            default_variant = next(
                (v for v in variants_ if v.get("default")),
                variants_[0] if variants_ else None,
            )
            if default_variant:
                config_base_version = default_variant.get("args", {}).get("BASE_VERSION")
    freebsd_major = extract_freebsd_major(
        config_base_version or pkg_base_version or cf_base_version
    )

    result = {}

    # Get pkg versions, per arch
    if pkg_name:
        q = get_pkg_versions_per_arch(pkg_name, "quarterly", freebsd_major)
        l = get_pkg_versions_per_arch(pkg_name, "latest", freebsd_major)

        if q:
            result["pkg"] = q
        if l:
            result["pkg-latest"] = l

    # Get upstream (binary) version -- a release version is arch-agnostic, so
    # this stays a scalar; the comparator applies it to every published arch.
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
        # schema 2: pkg/pkg-latest versions are per-arch objects ({arch: version});
        # `upstream` (binary release) stays a scalar. schema 1 had scalar pkg
        # versions -- the comparator keys off this to stay backward compatible.
        "schema_version": 2,
        "arches": list(ARCHES),
        "last_check": datetime.datetime.now(datetime.timezone.utc)
        .isoformat()
        .replace("+00:00", "Z"),
        "services": services,
    }

    print(json.dumps(output, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
