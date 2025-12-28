# FreeBSD Podman Containers

Native FreeBSD OCI containers using Podman and ocijail. Similar to [LinuxServer.io](https://www.linuxserver.io/) but for FreeBSD.

**[Documentation](https://daemonless.io)** | **[Quick Start](https://daemonless.io/quick-start/)** | **[Command Generator](https://daemonless.io/generator/)**

## Features

- s6 process supervision
- PUID/PGID support for permission handling
- FreeBSD 14.x and 15.x support
- Minimal image sizes (cleaned pkg cache)
- Port forwarding support with `-p` flag

## Quick Start

```bash
pkg install podman-suite cni-dnsname
```

See the full [Quick Start Guide](https://daemonless.io/quick-start/) for host configuration and setup.

### Run a Container

```bash
# Tautulli (no special annotations needed)
podman run -d --name tautulli \
  -p 8181:8181 \
  -e PUID=1000 -e PGID=1000 \
  -v /data/config/tautulli:/config \
  ghcr.io/daemonless/tautulli:latest

# Radarr (.NET app - requires patched ocijail)
podman run -d --name radarr \
  -p 7878:7878 \
  --annotation 'org.freebsd.jail.allow.mlock=true' \
  -e PUID=1000 -e PGID=1000 \
  -v /data/config/radarr:/config \
  ghcr.io/daemonless/radarr:latest
```

## Available Images

| Image | Port | Description |
|-------|------|-------------|
| [radarr](https://github.com/daemonless/radarr) | 7878 | Movie management |
| [sonarr](https://github.com/daemonless/sonarr) | 8989 | TV show management |
| [prowlarr](https://github.com/daemonless/prowlarr) | 9696 | Indexer management |
| [lidarr](https://github.com/daemonless/lidarr) | 8686 | Music management |
| [readarr](https://github.com/daemonless/readarr) | 8787 | Book management |
| [jellyfin](https://github.com/daemonless/jellyfin) | 8096 | Media server |
| [tautulli](https://github.com/daemonless/tautulli) | 8181 | Plex monitoring |
| [overseerr](https://github.com/daemonless/overseerr) | 5055 | Media requests |
| [sabnzbd](https://github.com/daemonless/sabnzbd) | 8080 | Usenet downloader |
| [transmission](https://github.com/daemonless/transmission) | 9091 | BitTorrent client |
| [transmission-wireguard](https://github.com/daemonless/transmission-wireguard) | 9091 | BitTorrent + VPN |
| [traefik](https://github.com/daemonless/traefik) | 80/443 | Reverse proxy |
| [gitea](https://github.com/daemonless/gitea) | 3000 | Self-hosted Git |
| [woodpecker](https://github.com/daemonless/woodpecker) | 8000 | CI/CD |
| [tailscale](https://github.com/daemonless/tailscale) | - | Mesh VPN |
| [organizr](https://github.com/daemonless/organizr) | 80 | Service dashboard |
| [smokeping](https://github.com/daemonless/smokeping) | 80 | Network latency |
| [openspeedtest](https://github.com/daemonless/openspeedtest) | 3000 | Speed test |
| [unifi](https://github.com/daemonless/unifi) | 8443 | UniFi Controller |
| [vaultwarden](https://github.com/daemonless/vaultwarden) | 80 | Password manager |
| [mealie](https://github.com/daemonless/mealie) | 9000 | Recipe manager |
| [nextcloud](https://github.com/daemonless/nextcloud) | 80 | File hosting |
| [n8n](https://github.com/daemonless/n8n) | 5678 | Workflow automation |

All images available as `:latest`, `:pkg`, and `:pkg-latest` tags.

## Documentation

- [Quick Start](https://daemonless.io/quick-start/) - Host setup and first container
- [Available Images](https://daemonless.io/images/) - Full image catalog with examples
- [Permissions](https://daemonless.io/guides/permissions/) - PUID/PGID explained
- [Networking](https://daemonless.io/guides/networking/) - Port forwarding vs host network
- [ocijail Patch](https://daemonless.io/guides/ocijail-patch/) - Required for .NET apps
- [ZFS Storage](https://daemonless.io/guides/zfs/) - Podman on ZFS

## Building Images Locally

```bash
# Build all images for FreeBSD 15
./scripts/local-build.sh 15

# Build specific image
./scripts/local-build.sh 15 radarr latest
./scripts/local-build.sh 15 radarr pkg

# Patch ocijail for .NET apps
./scripts/build-ocijail.sh
```

## Contributing

When adding or modifying images:

1. **Use `fetch`, not `curl`** - FreeBSD base includes `fetch`
2. **Sync `Containerfile.pkg`** - Keep labels/env/volumes consistent
3. **Label formatting** - Use `key="value"` format for OCI labels

## License

BSD 2-Clause License. See [LICENSE](LICENSE).
