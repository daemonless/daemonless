# User Permissions (PUID and PGID)

One of the most common challenges when using containers is handling file permissions between the host system and the container, especially when mounting local directories. The Daemonless project solves this using the `PUID` (User ID) and `PGID` (Group ID) environment variables.

## The Problem

By default, containers often run as `root` or a hardcoded user ID. When you mount a host directory (like `/mnt/data/media`) into a container, the files created by the container might be owned by `root` or a UID that doesn't exist on your host. Conversely, the container might not have permission to read files owned by your host user.

## The Solution: PUID and PGID

Images in this project include a `bsd` user. At startup, an initialization script reads the `PUID` and `PGID` environment variables you provide and automatically reconfigures the internal `bsd` user to match those IDs.

This ensures that any files written by the application inside the container appear on your host as being owned by your specific user account.

## How to Find Your IDs

On your FreeBSD host, run the `id` command for the user you want the container to "act" as:

```bash
$ id ahze
uid=1001(ahze) gid=1001(ahze) groups=1001(ahze),0(wheel)
```

In this example, the `PUID` is `1001` and the `PGID` is `1001`.

## Usage

### Podman CLI

Pass the IDs as environment variables using the `-e` flag:

```bash
podman run -d --name radarr \
  -e PUID=1001 \
  -e PGID=1001 \
  -v /data/config/radarr:/config \
  ghcr.io/daemonless/radarr:latest
```

### podman-compose

Add them to the `environment` section of your `compose.yaml`:

```yaml
services:
  radarr:
    image: ghcr.io/daemonless/radarr:latest
    environment:
      - PUID=1001
      - PGID=1001
    volumes:
      - /data/config/radarr:/config
```

## Automatic Directory Handling

The base image automatically ensures that the `/config` directory inside the container is owned by the `PUID`/`PGID` you specify. 

However, for **additional volumes** (like `/movies` or `/downloads`), the container will not automatically change permissions recursively (to avoid slow startup times on large libraries). You should ensure that your host user has appropriate read/write access to those directories before starting the container.

## Technical Details

- **Internal User:** The application process inside the container is executed using `s6-setuidgid bsd`.
- **Default:** if no variables are provided, the container defaults to `PUID=1000` and `PGID=1000`.
- **Implementation:** The logic is handled by `/etc/cont-init.d/10-usermod` which runs before the application starts.
