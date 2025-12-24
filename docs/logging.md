# Internal Log Rotation

Daemonless images feature a built-in log rotation system powered by `s6-log`. This ensures that your container logs are persistent, rotated, and size-capped to prevent disk exhaustion.

## How it Works

Every application process in a Daemonless container is paired with a logging consumer service. 
1. The application prints its output to the console (stdout/stderr).
2. `s6` pipes that output directly into `s6-log`.
3. `s6-log` saves the output to disk **and** mirrors it back to the console so `podman logs` continues to work.

## Log Locations

- **System Console Logs**: `/config/logs/daemonless/<app-name>/current`
- **Application-Internal Logs**: Typically in `/config/logs/` or as defined by the application.

## Configuration

You can control the logging behavior using the following environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `S6_LOG_ENABLE` | Set to `0` to disable writing logs to disk. | `1` |
| `S6_LOG_MAX_SIZE` | Maximum size of a single log file in bytes. | `1048576` (1MB) |
| `S6_LOG_MAX_FILES` | Number of rotated log files to keep. | `10` |
| `S6_LOG_STDOUT` | Set to `0` to stop mirroring logs to the console (`podman logs`). | `1` |
| `S6_LOG_DEST` | The root directory where logs are stored. | `/config/logs/daemonless` |

### Examples

**Increase log retention:**
```bash
podman run -e S6_LOG_MAX_FILES=50 ghcr.io/daemonless/sonarr
```

**Disable disk logging (Stdout only):**
```bash
podman run -e S6_LOG_ENABLE=0 ghcr.io/daemonless/sonarr
```

## Why Persistent Logs?

By storing logs in `/config/logs/daemonless/`, your troubleshooting history survives container updates and recreations. This is especially useful on FreeBSD where native jail logs are often preferred for long-term monitoring.
