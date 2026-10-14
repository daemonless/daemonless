# Scripts

This directory contains utility scripts for the Daemonless project.

Most image build, test, lint, and documentation tasks are handled by
**[dbuild](https://github.com/daemonless/dbuild)** — run `dbuild --help` for usage.

## generate_versions.py

Generates `daemonless-versions.json` by fetching version info from GitHub.

```bash
python3 scripts/generate_versions.py
```

## new-image-repo.sh

Creates `daemonless/<name>` on GitHub with the build workflow already on
`main`, so the first contributor PR gets CI (build and `dbuild lint`). A PR
that adds the workflow itself runs nothing. Pushes only `README.md` and the
workflow, with `[skip ci]`: no image is built and no ghcr package is made.

```bash
sh scripts/new-image-repo.sh -n node-red "Low-code programming for event-driven applications"   # dry run
sh scripts/new-image-repo.sh node-red "Low-code programming for event-driven applications"
```
