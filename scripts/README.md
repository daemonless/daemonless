# Scripts

This directory contains utility scripts for the Daemonless project.

## build-ocijail.sh

This script builds a custom version of `ocijail` patched to support extended FreeBSD jail parameters (like `allow.mlock`) via OCI annotations. 

### Usage

```bash
doas ./build-ocijail.sh
```

### Documentation

For detailed information on why this patch is needed, how the automated script works, and instructions for manual installation via the ports system, please see:

**[ocijail Patch Documentation](../docs/ocijail-patch.md)**
