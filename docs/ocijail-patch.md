# ocijail Patch

To fully support modern applications like .NET apps and databases, the Daemonless project uses a patched version of **ocijail**.

## Why is a patch needed?

FreeBSD Jails have several "allow" parameters (e.g., `allow.mlock`, `allow.sysvipc`, `allow.raw_sockets`) that control what processes inside the jail are permitted to do. 

The stock `ocijail` runtime (used by Podman on FreeBSD) doesn't yet provide a way to pass generic `allow.*` flags through the OCI specification.

### Key Use Cases
- **.NET Applications** (Radarr, Sonarr, etc.): Require `allow.mlock` for memory management.
- **Databases** (PostgreSQL): Often require `allow.sysvipc` for shared memory.
- **Network Tools**: Require `allow.raw_sockets` for ping functionality.

## The Daemonless Patch

Our patch adds support for mapping OCI annotations directly to jail parameters. Any annotation prefixed with `org.freebsd.jail.allow.` is automatically translated to the corresponding `allow.` jail parameter.

**Example Translation:**
`--annotation org.freebsd.jail.allow.mlock=true`  =>  `allow.mlock`

---

## Installation

You can apply this patch using our automated script or manually via the ports system.

### Option 1: Automated Script (Recommended)

This script creates a temporary overlay of the port (if found) or clones the git repository, applies the patch, and installs the binary. It is the fastest way to get running without "dirtying" your system's ports tree.

```bash
# Run from the root of the daemonless repository
doas ./scripts/build-ocijail.sh
```

**What the script does:**
1.  **Ports Overlay:** If `/usr/ports/sysutils/ocijail` exists, it copies it to a temporary directory.
2.  **Patching:** It injects the `patch-daemonless-annotations` into the build.
3.  **Building:** It uses the native ports framework or `bazel` to build the binary.
4.  **Installation:** It backs up your original binary and installs the patched version to `/usr/local/bin/ocijail`.

### Option 2: Manual Ports Method

If you prefer to patch the port yourself using the standard FreeBSD ports system:

1.  **Download the patch** from the `scripts/` directory and copy it to the port's files directory:
    ```bash
    cp scripts/ocijail-allow-annotations.patch /usr/ports/sysutils/ocijail/files/patch-daemonless-annotations
    ```

2.  **Rebuild and Install**:
    ```bash
    cd /usr/ports/sysutils/ocijail
    make reinstall clean
    ```

---

## Verification

You can verify the patch is working by running a container with an annotation and checking the jail properties on the host.

1. Start a container with an annotation:
```bash
podman run -d --name test-jail --annotation 'org.freebsd.jail.allow.mlock=true' ghcr.io/daemonless/base-image:15 sleep infinity
```

2. Check the jail parameters from your FreeBSD host:
```bash
jexec test-jail sysctl security.jail.param.allow.mlock
```
If the output is `security.jail.param.allow.mlock: 1`, the patch is active and working.

## Upstream Status

We reached out to the `ocijail` maintainer, Doug Rabson (`dfr@`), regarding this functionality. 

The long-term plan for `ocijail` is to support jail parameters through the new **FreeBSD extensions in the OCI v1.3.0 runtime specification**. Support for these extensions is being developed for both `ocijail` and Podman.

In the meantime, Doug has agreed that adding annotation-based controls (as implemented in our patch) makes sense as a transitionary solution and plans to integrate this functionality into the main `ocijail` repository soon.