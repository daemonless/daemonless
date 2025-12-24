# Quick Start Guide

This guide will take you from a fresh FreeBSD installation to running your first native OCI container using Podman and ocijail.

## 1. Install Prerequisites

Install the necessary tools for Podman and for building the ocijail patch.

```bash
pkg install podman ocijail bazel git
```

## 2. Configure Host System

FreeBSD requires specific configuration for container networking and process management.

### System Settings
Enable local filtering for `pf` and mount `fdescfs`:

```bash
# Enable pf local filtering (for port forwarding)
sysctl net.pf.filter_local=1
echo 'net.pf.filter_local=1' >> /etc/sysctl.conf

# Mount fdescfs (required for conmon)
mount -t fdescfs fdesc /dev/fd
echo 'fdesc /dev/fd fdescfs rw 0 0' >> /etc/fstab

# Enable podman service
sysrc podman_enable=YES
```

### PF Configuration
Add these lines to `/etc/pf.conf` to enable container networking:

```pf
# Podman container networking
rdr-anchor "cni-rdr/*"
nat-anchor "cni-rdr/*"
table <cni-nat>
nat on $ext_if inet from <cni-nat> to any -> ($ext_if)
nat on $ext_if inet from 10.88.0.0/16 to any -> ($ext_if)
```
*Replace `$ext_if` with your actual network interface (e.g., `vtnet0`, `re0`).*

Reload pf: `pfctl -f /etc/pf.conf`

## 3. Apply ocijail Patch

To support .NET apps and databases, you must apply the Daemonless patch to `ocijail`.

```bash
git clone https://github.com/daemonless/daemonless.git
cd daemonless
./scripts/build-ocijail.sh
```
*See [ocijail Patch Documentation](ocijail-patch.md) for more details.*

## 4. Storage Setup (Optional but Recommended)

For best performance, configure Podman to use ZFS:

```bash
zfs create -o mountpoint=/var/db/containers/storage zroot/podman
```
*See [ZFS Storage Setup](zfs.md) for the required `/etc/containers/storage.conf` configuration.*

## 5. Run Your First Container

You can now run a native FreeBSD container. Let's start a simple Radarr instance as an example:

```bash
podman run -d --name radarr \
  -p 7878:7878 \
  --annotation 'org.freebsd.jail.allow.mlock=true' \
  -e PUID=1000 -e PGID=1000 \
  -v /data/config/radarr:/config \
  ghcr.io/daemonless/radarr:latest
```

Access the web interface at: `http://<your-host-ip>:7878`

## Next Steps

- Explore available images in the `repos/` directory.
- Learn about [User Permissions (PUID/PGID)](permissions.md).
- Understand different [Networking Modes](networking.md).
- Use [podman-compose](https://github.com/containers/podman-compose) for multi-container stacks.
