# Scripts

This directory contains utility scripts for the Daemonless project.

Most image build, test, lint, and documentation tasks are handled by
**[dbuild](https://github.com/daemonless/dbuild)** — run `dbuild --help` for usage.

## generate_versions.py

Generates `daemonless-versions.json` by fetching version info from GitHub.

```bash
python3 scripts/generate_versions.py
```
