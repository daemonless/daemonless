<!--
Standard README template for daemonless application repositories.
Copy this to repos/<app>/README.md and fill in the placeholders.
-->

# {{APP_NAME}}

{{DESCRIPTION}}

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PUID` | User ID for the application process | `1000` |
| `PGID` | Group ID for the application process | `1000` |
| `TZ` | Timezone for the container | `UTC` |
| `S6_LOG_ENABLE` | Enable/Disable file logging | `1` |
| `S6_LOG_MAX_SIZE` | Max size per log file (bytes) | `1048576` |
| `S6_LOG_MAX_FILES` | Number of rotated log files to keep | `10` |

## Logging

This image uses `s6-log` for internal log rotation.
- **System Logs**: Captured from console and stored at `/config/logs/daemonless/{{APP_NAME}}/`.
- **Application Logs**: Managed by the app and typically found in `/config/logs/`.
- **Podman Logs**: Output is mirrored to the console, so `podman logs` still works.

## Quick Start

```bash
podman run -d --name {{APP_NAME}} \
  -p {{PORT}}:{{PORT}} \
  -e PUID=1000 -e PGID=1000 \
  -v /path/to/config:/config \
  ghcr.io/daemonless/{{APP_NAME}}:latest
```

Access at: http://localhost:{{PORT}}

## podman-compose

```yaml
services:
  {{APP_NAME}}:
    image: ghcr.io/daemonless/{{APP_NAME}}:latest
    container_name: {{APP_NAME}}
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    volumes:
      - /data/config/{{APP_NAME}}:/config
    ports:
      - {{PORT}}:{{PORT}}
    restart: unless-stopped
```

## Tags

| Tag | Source | Description |
|-----|--------|-------------|
| `:latest` | [Upstream Releases]({{UPSTREAM_URL}}) | Latest upstream release |
| `:pkg` | `{{PKG_NAME}}` | FreeBSD quarterly packages |
| `:pkg-latest` | `{{PKG_NAME}}` | FreeBSD latest packages |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PUID` | 1000 | User ID for app |
| `PGID` | 1000 | Group ID for app |
| `TZ` | UTC | Timezone |

## Volumes

| Path | Description |
|------|-------------|
| `/config` | Configuration directory |

## Ports

| Port | Description |
|------|-------------|
| {{PORT}} | Web UI |

## Notes

- **User:** `bsd` (UID/GID set via PUID/PGID, default 1000)
- **Healthcheck:** `--health-cmd /healthz`
- **Base:** Built on `ghcr.io/daemonless/base-image` (FreeBSD)

### Specific Requirements
<!-- Uncomment if applicable -->
<!-- - **.NET App:** Requires `--annotation 'org.freebsd.jail.allow.mlock=true'` (Requires [patched ocijail](https://github.com/daemonless/daemonless#ocijail-patch)) -->
<!-- - **Raw Sockets:** Requires `--annotation 'org.freebsd.jail.allow.raw_sockets=true'` (e.g. for ping) -->
<!-- - **VNET:** Requires `--annotation 'org.freebsd.jail.vnet=new'` -->

## Links

- [Website]({{WEBSITE_URL}})
- [FreshPorts]({{FRESHPORTS_URL}})
