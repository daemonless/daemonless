# Scripts

This directory contains utility scripts for the Daemonless project.

Most image build, test, lint, and documentation tasks are handled by
**[dbuild](https://github.com/daemonless/dbuild)** — run `dbuild --help` for usage.

## build-ocijail.sh

Builds a patched version of `ocijail` with support for extended FreeBSD jail
parameters (like `allow.mlock`) via OCI annotations. Required for .NET apps.

```bash
doas ./build-ocijail.sh
```

See **[ocijail Patch Documentation](../docs/ocijail-patch.md)** for details.

## compare-versions.py

Compares `daemonless-versions.json` against deployed tags on ghcr.io to show
which images are out of date.

```bash
python3 scripts/compare-versions.py
```

## generate_versions.py

Generates `daemonless-versions.json` by fetching version info from GitHub.

```bash
python3 scripts/generate_versions.py
```
