#!/usr/bin/env python3
"""
Lint daemonless repos for common issues.
"""
import yaml
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent.parent.parent

REQUIRED_X_DAEMONLESS_FIELDS = [
    "title",
    "icon",
    "category",
    "description",
    "upstream_url",
    "user",
]

VALID_CATEGORIES = [
    "Base",
    "Databases",
    "Development",
    "Downloaders",
    "Infrastructure",
    "Media Management",
    "Media Servers",
    "Monitoring",
    "Network",
    "Networking",
    "Photos & Media",
    "Productivity",
    "Security",
    "Utilities",
]

SKIP_REPOS = [
    ".github",
    "arr-base",
    "base",
    "ci-daemonless-io",
    "cit",
    "daemonless",
    "daemonless-io",
    "dbuild",
    "freebsd-ports",
    "immich",  # Stack, not individual image
    "nginx-base",
]


def lint_repo(repo_path: Path) -> tuple[list[str], list[str]]:
    """Lint a single repo, return (errors, warnings)."""
    errors = []
    warnings = []
    name = repo_path.name

    compose_path = repo_path / "compose.yaml"
    config_path = repo_path / ".daemonless" / "config.yaml"

    # Must have either compose.yaml or .daemonless/config.yaml
    if not compose_path.exists() and not config_path.exists():
        errors.append(f"Missing compose.yaml and .daemonless/config.yaml")
        return errors, warnings

    # Check compose.yaml for x-daemonless
    if compose_path.exists():
        with open(compose_path) as f:
            try:
                data = yaml.safe_load(f)
            except yaml.YAMLError as e:
                errors.append(f"Invalid YAML in compose.yaml: {e}")
                return errors, warnings

        if not data:
            errors.append(f"Empty compose.yaml")
            return errors, warnings

        meta = data.get("x-daemonless", {})

        if not meta:
            errors.append(f"Missing x-daemonless metadata block in compose.yaml")
        else:
            # Check required fields
            for field in REQUIRED_X_DAEMONLESS_FIELDS:
                if field not in meta or not meta[field]:
                    errors.append(f"Missing required field: x-daemonless.{field}")

            # Validate category
            category = meta.get("category", "")
            if category and category not in VALID_CATEGORIES:
                errors.append(f"Invalid category '{category}'. Valid: {', '.join(VALID_CATEGORIES)}")

            # Check icon format
            icon = meta.get("icon", "")
            if icon and not (icon.startswith(":") and icon.endswith(":")):
                errors.append(f"Invalid icon format '{icon}'. Should be :icon-name:")

            # Check docs section
            docs = meta.get("docs", {})
            if isinstance(docs, dict):
                # If there are env vars in service, docs.env should document them
                services = data.get("services", {})
                if services:
                    service = list(services.values())[0]
                    env_vars = service.get("environment", [])
                    if isinstance(env_vars, list):
                        env_keys = [e.split("=")[0] for e in env_vars if "=" in e]
                    else:
                        env_keys = list(env_vars.keys())

                    # Skip common vars that don't need docs
                    skip_vars = ["PUID", "PGID", "TZ"]
                    doc_env = docs.get("env", {})

                    for key in env_keys:
                        if key not in skip_vars and key not in doc_env:
                            warnings.append(f"Undocumented env var: {key} (add to x-daemonless.docs.env)")

    # Check .daemonless/config.yaml
    if config_path.exists():
        with open(config_path) as f:
            try:
                config = yaml.safe_load(f)
            except yaml.YAMLError as e:
                errors.append(f"Invalid YAML in .daemonless/config.yaml: {e}")
                return errors, warnings

        if not config:
            errors.append(f"Empty .daemonless/config.yaml")
            return errors, warnings

        # Check build config
        build = config.get("build", {})
        if build:
            # Architectures should be a list
            archs = build.get("architectures", [])
            if archs and not isinstance(archs, list):
                errors.append(f"build.architectures should be a list")

            # Validate architecture values
            valid_archs = ["amd64", "aarch64", "riscv64"]
            for arch in archs:
                if arch not in valid_archs:
                    errors.append(f"Invalid architecture '{arch}'. Valid: {', '.join(valid_archs)}")

    # Check Containerfile exists
    has_containerfile = (
        (repo_path / "Containerfile").exists() or
        (repo_path / "Containerfile.j2").exists() or
        (repo_path / "Containerfile.pkg").exists() or
        (repo_path / "Containerfile.pkg.j2").exists()
    )
    if not has_containerfile:
        errors.append(f"Missing Containerfile")

    return errors, warnings


def main():
    all_errors = {}
    all_warnings = {}

    for repo in sorted(REPO_ROOT.glob("daemonless/*")):
        if not repo.is_dir() or repo.name in SKIP_REPOS:
            continue

        errors, warnings = lint_repo(repo)
        if errors:
            all_errors[repo.name] = errors
        if warnings:
            all_warnings[repo.name] = warnings

    if all_warnings:
        print("WARNINGS:")
        print("=" * 60)
        for name, warnings in sorted(all_warnings.items()):
            print(f"\n{name}:")
            for warn in warnings:
                print(f"  - {warn}")

    if all_errors:
        print("\nERRORS:")
        print("=" * 60)
        for name, errors in sorted(all_errors.items()):
            print(f"\n{name}:")
            for err in errors:
                print(f"  - {err}")
        print(f"\n{len(all_errors)} repos with errors")
        sys.exit(1)
    else:
        print("\nAll repos passed lint checks")
        sys.exit(0)


if __name__ == "__main__":
    main()
