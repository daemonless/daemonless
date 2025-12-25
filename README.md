# FreeBSD Podman Containers

Native FreeBSD OCI containers using Podman and ocijail. Similar to [LinuxServer.io](https://www.linuxserver.io/) but for FreeBSD.

**[Command Generator](https://daemonless.github.io/daemonless/)** - Interactive tool to generate `podman run` commands and compose files.

## Features

- s6 process supervision
- PUID/PGID support for permission handling
- FreeBSD 14.x and 15.x support
- Minimal image sizes (cleaned pkg cache)
- Port forwarding support with `-p` flag

## Quick Start

### Prerequisites

```bash
# Install podman and ocijail
pkg install podman ocijail bazel git

# For .NET apps (Radarr, Sonarr, etc.), patch ocijail:
./scripts/build-ocijail.sh
```

### Host Configuration

FreeBSD Podman requires pf configuration for container networking:

```bash
# Enable pf local filtering (required for port forwarding)
sysctl net.pf.filter_local=1
echo 'net.pf.filter_local=1' >> /etc/sysctl.conf

# Mount fdescfs (required for conmon)
mount -t fdescfs fdesc /dev/fd
echo 'fdesc /dev/fd fdescfs rw 0 0' >> /etc/fstab

# Enable podman service
sysrc podman_enable=YES
```

Add these lines to `/etc/pf.conf`:

```
# Podman container networking (port forwarding support)
rdr-anchor "cni-rdr/*"
nat-anchor "cni-rdr/*"
table <cni-nat>
nat on $ext_if inet from <cni-nat> to any -> ($ext_if)
nat on $ext_if inet from 10.88.0.0/16 to any -> ($ext_if)
```

Then reload pf: `pfctl -f /etc/pf.conf`

### Build Images

```bash
# Build all images for FreeBSD 15 (:latest tag)
./scripts/local-build.sh 15

# Build specific image with specific tag
./scripts/local-build.sh 15 radarr latest
./scripts/local-build.sh 15 radarr pkg
./scripts/local-build.sh 15 radarr pkg-latest

# Build all :pkg images
./scripts/local-build.sh 15 all pkg

# For FreeBSD 14
./scripts/local-build.sh 14
```

### Run Containers

```bash
# Radarr (requires allow.mlock for .NET)
podman run -d --name radarr \
  -p 7878:7878 \
  --annotation 'org.freebsd.jail.allow.mlock=true' \
  -e PUID=1000 -e PGID=1000 \
  -v /path/to/config:/config \
ghcr.io/daemonless/radarr:latest

# Tautulli (Python app, no special annotations needed)
podman run -d --name tautulli \
  -p 8181:8181 \
  -e PUID=1000 -e PGID=1000 \
  -v /path/to/config:/config \
  ghcr.io/daemonless/tautulli:latest
```

### podman-compose

Install podman-compose:
```bash
pkg install py311-podman-compose
```

Create a `compose.yaml`:

```yaml
services:
  radarr:
    image: ghcr.io/daemonless/radarr:latest
    container_name: radarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    volumes:
      - /data/config/radarr:/config
      - /data/media/movies:/movies
      - /data/downloads:/downloads
    ports:
      - 7878:7878
    annotations:
      org.freebsd.jail.allow.mlock: "true"
    restart: unless-stopped

  sonarr:
    image: ghcr.io/daemonless/sonarr:latest
    container_name: sonarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    volumes:
      - /data/config/sonarr:/config
      - /data/media/tv:/tv
      - /data/downloads:/downloads
    ports:
      - 8989:8989
    annotations:
      org.freebsd.jail.allow.mlock: "true"
    restart: unless-stopped

  prowlarr:
    image: ghcr.io/daemonless/prowlarr:latest
    container_name: prowlarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    volumes:
      - /data/config/prowlarr:/config
    ports:
      - 9696:9696
    annotations:
      org.freebsd.jail.allow.mlock: "true"
    restart: unless-stopped

  tautulli:
    image: ghcr.io/daemonless/tautulli:latest
    container_name: tautulli
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    volumes:
      - /data/config/tautulli:/config
    ports:
      - 8181:8181
    restart: unless-stopped

  overseerr:
    image: ghcr.io/daemonless/overseerr:latest
    container_name: overseerr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    volumes:
      - /data/config/overseerr:/config
    ports:
      - 5055:5055
    restart: unless-stopped
```

Run the stack:
```bash
podman-compose up -d
```

## Available Images

| Image | Port | Description | Tags |
|-------|------|-------------|------|
| [radarr](https://github.com/daemonless/radarr) | 7878 | Movie management | `:latest`, `:pkg`, `:pkg-latest` |
| [sonarr](https://github.com/daemonless/sonarr) | 8989 | TV show management | `:latest`, `:pkg`, `:pkg-latest` |
| [prowlarr](https://github.com/daemonless/prowlarr) | 9696 | Indexer management | `:latest`, `:pkg`, `:pkg-latest` |
| [lidarr](https://github.com/daemonless/lidarr) | 8686 | Music management | `:latest`, `:pkg`, `:pkg-latest` |
| [readarr](https://github.com/daemonless/readarr) | 8787 | Book management | `:latest`, `:pkg`, `:pkg-latest` |
| [tautulli](https://github.com/daemonless/tautulli) | 8181 | Plex monitoring | `:latest`, `:pkg`, `:pkg-latest` |
| [overseerr](https://github.com/daemonless/overseerr) | 5055 | Media requests | `:latest`, `:pkg`, `:pkg-latest` |
| [sabnzbd](https://github.com/daemonless/sabnzbd) | 8080 | Usenet downloader | `:latest`, `:pkg`, `:pkg-latest` |
| [transmission](https://github.com/daemonless/transmission) | 9091 | BitTorrent client | `:latest`, `:pkg`, `:pkg-latest` |
| [transmission-wireguard](https://github.com/daemonless/transmission-wireguard) | 9091 | BitTorrent + VPN | `:latest`, `:pkg`, `:pkg-latest` |
| [openspeedtest](https://github.com/daemonless/openspeedtest) | 3000 | Network speed test | `:latest`, `:pkg`, `:pkg-latest` |
| [organizr](https://github.com/daemonless/organizr) | 80 | Service dashboard | `:latest`, `:pkg`, `:pkg-latest` |
| [unifi](https://github.com/daemonless/unifi) | 8443 | UniFi Network Controller | `:latest`, `:pkg`, `:pkg-latest` |
| [smokeping](https://github.com/daemonless/smokeping) | 80 | Network latency monitoring | `:latest`, `:pkg`, `:pkg-latest` |
| [traefik](https://github.com/daemonless/traefik) | 80/443/8080 | Reverse proxy | `:latest`, `:pkg`, `:pkg-latest` |
| [gitea](https://github.com/daemonless/gitea) | 3000 | Self-hosted Git | `:latest`, `:pkg`, `:pkg-latest` |
| [tailscale](https://github.com/daemonless/tailscale) | - | Mesh VPN | `:latest`, `:pkg`, `:pkg-latest` |
| [mealie](https://github.com/daemonless/mealie) | 9000 | Recipe manager | `:latest`, `:pkg`, `:pkg-latest` |
| [nextcloud](https://github.com/daemonless/nextcloud) | 80 | File hosting | `:latest`, `:pkg`, `:pkg-latest` |
| [n8n](https://github.com/daemonless/n8n) | 5678 | Workflow automation | `:latest`, `:pkg`, `:pkg-latest` |
| [jellyfin](https://github.com/daemonless/jellyfin) | 8096 | Media Server | `:latest`, `:pkg`, `:pkg-latest` |
| [vaultwarden](https://github.com/daemonless/vaultwarden) | 80 | Password Manager | `:latest`, `:pkg`, `:pkg-latest` |
| [woodpecker](https://github.com/daemonless/woodpecker) | 8000 | CI/CD | `:latest`, `:pkg`, `:pkg-latest` |

### Image Tags

| Tag | Source | Description |
|-----|--------|-------------|
| `:latest` | Servarr API / GitHub | Newest upstream release |
| `:pkg` | FreeBSD quarterly packages | Stable, tested in ports |
| `:pkg-latest` | FreeBSD latest packages | Rolling package updates |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PUID` | 1000 | User ID for app |
| `PGID` | 1000 | Group ID for app |
| `TZ` | UTC | Timezone |

## Technologies

The Daemonless project leverages several key FreeBSD and container technologies:

- **[Podman](https://podman.io/)**: The primary engine used to manage OCI containers.
- **[ocijail](https://github.com/dfr/ocijail)**: The OCI-compatible runtime that maps OCI lifecycle commands to FreeBSD jails.
- [s6-overlay](https://github.com/just-containers/s6-overlay)**: We use a simplified [s6](https://skarnet.org/software/s6/) setup inspired by s6-overlay for process supervision and initialization.
- **[FreeBSD Jails](https://www.freebsd.org/jails/)**: The underlying OS-level virtualization technology.

## Project Structure

```
daemonless/
├── scripts/
│   ├── build-ocijail.sh                # Build patched ocijail
│   ├── local-build.sh                  # Local multi-image build script
│   └── README.md                       # Scripts documentation
├── docs/                    # GitHub Pages documentation
├── TEMPLATE.md              # Standard README template for app repos
└── README.md
```

**Repositories are now split into separate repos:**
- `repos/base-image` (was `base-images/runtime`)
- `repos/nginx-base-image` (was `base-images/nginx`)
- `repos/<app>` (e.g., `repos/radarr`)


## Documentation

- [Quick Start Guide](/docs/quick-start.md) - Get up and running on FreeBSD.
- [User Permissions](/docs/permissions.md) - Handling file permissions with PUID and PGID.
- [Log Rotation](/docs/logging.md) - How internal log rotation works and how to configure it.
- [ocijail Patch](/docs/ocijail-patch.md) - Why and how to patch ocijail for custom annotations.
- [ZFS Storage Setup](/docs/zfs.md) - Configuring Podman to use ZFS on FreeBSD.
- [Metadata Labels](/docs/labels.md) - Overview of OCI and custom labels used in images.

## Networking

FreeBSD Podman supports two networking modes:

### Port Forwarding (Recommended)
```bash
podman run -d -p 7878:7878 --name radarr localhost/radarr:latest
```
Requires pf configuration (see Host Configuration above).

### Host Network
```bash
podman run -d --network=host --name radarr localhost/radarr:latest
```
Container shares host network namespace directly. Simpler but less isolated.

## ocijail Patch

.NET applications require the `allow.mlock` jail parameter to function. Stock ocijail doesn't support setting `allow.*` parameters via annotations. This patch adds support for `org.freebsd.jail.allow.*` annotations.

### Why This Is Needed

FreeBSD jails have various `allow.*` parameters that control what operations are permitted inside the jail. Some applications require specific permissions:

| Parameter | Required By | Purpose |
|-----------|-------------|---------|
| `allow.mlock` | .NET apps (Radarr, Sonarr, etc.) | Memory locking for garbage collection |
| `allow.raw_sockets` | Uptime Kuma, ping tools | ICMP ping functionality |

### Installation

```bash
# Run on your FreeBSD host (requires bazel, git)
./scripts/build-ocijail.sh
```

This script:
1. Clones [ocijail](https://github.com/dfr/ocijail) to `/tmp/ocijail`
2. Applies `ocijail-allow-annotations.patch`
3. Builds with Bazel
4. Installs to `/usr/local/bin/ocijail` (backs up original)

### Usage

After patching, use annotations to enable jail parameters:

```bash
# For .NET apps
podman run -d --name radarr \
  --annotation 'org.freebsd.jail.allow.mlock=true' \
ghcr.io/daemonless/radarr:latest

# For ping functionality
podman run -d --name uptime-kuma \
  --annotation 'org.freebsd.jail.allow.raw_sockets=true' \
  localhost/uptime-kuma:latest
```

### Supported Annotations

Any `allow.*` jail parameter can be set via annotation:

| Annotation | Jail Parameter |
|------------|----------------|
| `org.freebsd.jail.allow.mlock=true` | `allow.mlock` |
| `org.freebsd.jail.allow.raw_sockets=true` | `allow.raw_sockets` |
| `org.freebsd.jail.allow.chflags=true` | `allow.chflags` |

See `jail(8)` for all available parameters.

### Upstream Status

This patch has not yet been submitted upstream to ocijail. The stock ocijail supports `org.freebsd.jail.vnet` but not the generic `allow.*` parameters.

## CI/CD

Images are automatically built and pushed to `ghcr.io/daemonless/*` via Woodpecker CI.

### Architecture

- **Gitea** (`gitea.ahze.lan`): Git hosting, triggers webhooks on push
- **Woodpecker Server**: Runs in container on saturn
- **Woodpecker Agent**: Runs on host (FreeBSD rc service), uses local backend
- **Registry**: GitHub Container Registry (`ghcr.io/daemonless/*`)

### Pipeline

Each repo has a `.woodpecker.yml` that:
1. Syncs repo to latest
2. Builds image with `doas podman build`
3. Pushes to `ghcr.io/daemonless/<image>:latest`

### WIP Images

Images marked with `io.daemonless.wip="true"` in their Containerfile are work-in-progress and disabled in CI:
- mealie
- n8n

### Adding a New Image

1. Create repo in Gitea
2. Add `.woodpecker.yml` (copy from existing repo)
3. Activate repo in Woodpecker UI
4. Push to trigger build

## License

BSD 2-Clause License. See [LICENSE](LICENSE).

## Development

### Contributing
When adding or modifying images:

1.  **Use `fetch`, not `curl`**: FreeBSD base includes `fetch`. Using `curl` requires installing an extra package.
    ```dockerfile
    RUN fetch -o /tmp/file.tar.gz https://example.com/file.tar.gz
    ```
2.  **Sync `Containerfile.pkg`**: If an image has a `.pkg` variant, ensure changes (Labels, Env, Volumes) are mirrored in `Containerfile.pkg`.
3.  **Label Formatting**: Use standard `key="value"` format for OCI labels to ensure the documentation generator works correctly.

## References

- [OCI Runtime Specification](https://github.com/opencontainers/runtime-spec)
- [OCI Containers on FreeBSD (FreeBSD Foundation)](https://freebsdfoundation.org/blog/oci-containers-on-freebsd/)
- [Podman Installation - FreeBSD](https://podman.io/docs/installation)
- [ocijail GitHub](https://github.com/dfr/ocijail)
- [FreshPorts: sysutils/podman](https://www.freshports.org/sysutils/podman/)
- [FreshPorts: sysutils/ocijail](https://www.freshports.org/sysutils/ocijail/)
