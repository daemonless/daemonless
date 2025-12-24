# ZFS Storage Setup

FreeBSD users should use the **ZFS storage driver** for Podman. It provides superior performance, native copy-on-write layering, and efficient space management compared to the default `vfs` driver.

## 1. Create a ZFS Dataset

It is recommended to create a dedicated dataset for container storage. This allows you to manage quotas, snapshots, and compression independently.

```bash
# Create the dataset (adjust 'zroot' to your pool name)
zfs create -o mountpoint=/var/db/containers/storage zroot/podman
```

## 2. Configure Podman

You must tell Podman to use the ZFS driver by editing (or creating) `/etc/containers/storage.conf`.

### Standard Configuration
Create or edit `/etc/containers/storage.conf`:

```ini
[storage]
driver = "zfs"
runroot = "/var/run/containers/storage"
graphroot = "/var/db/containers/storage"

[storage.options]
# Optional: Set a specific ZFS dataset if not using the mountpoint above
# zfs.fsname = "zroot/podman"
```

## 3. Verify the Configuration

After configuring the storage driver, verify that Podman is using it correctly:

```bash
podman info | grep -A 5 "store"
```

You should see output similar to:
```yaml
...
graphDriverName: zfs
graphRoot: /var/db/containers/storage
graphStatus:
  Dataset: zroot/podman
...
```

## Troubleshooting

### "driver zfs is not supported"
If you see an error indicating ZFS is not supported, ensure that:
1. Your ZFS pool is imported and healthy.
2. The `graphroot` directory exists and is a ZFS dataset.
3. You are running Podman as `root` (or have appropriate permissions if using rootless, though rootless ZFS on FreeBSD has additional complexities).

### Slow Image Pulls
If image pulls are slow, ensure that `compression=on` (or `lz4`) is set on your Podman dataset:
```bash
zfs set compression=lz4 zroot/podman
```
