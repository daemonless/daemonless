# Init System (s6 Supervision)

Daemonless containers use a custom initialization system based on **s6-svscan**. This system is designed to provide process supervision, handle multi-process containers (like UniFi or Mealie), and allow for flexible runtime configuration.

## The /init Script

The entrypoint for all containers is the `/init` script. Its primary responsibilities are:

1.  **Environment Handling**: It captures all environment variables passed to the container and saves them so they are available to supervised services.
2.  **Networking**: It automatically configures the loopback interface (`lo0`), which is essential for health checks and internal communication.
3.  **Initialization**: It executes startup scripts in a specific order (see below).
4.  **Supervision**: It starts `s6-svscan` to monitor and manage application processes.

## Initialization Sequence

When a container starts, `/init` runs scripts from the following directories in order:

### 1. Built-in Init (/etc/cont-init.d/)
These scripts are part of the container image. They handle internal setup like configuring the `bsd` user (PUID/PGID), setting permissions on `/config`, and generating default configuration files.

### 2. Custom Init (/custom-cont-init.d/)
This directory is intended for **user-provided scripts**. If you mount a directory of scripts to this path, they will be executed after the built-in scripts but before the application starts.

**Example:**
```bash
podman run -d \
  -v /path/to/my-scripts:/custom-cont-init.d:ro \
  ghcr.io/daemonless/radarr:latest
```

## Service Management

Processes are supervised by `s6`. This means if the application crashes, s6 will automatically attempt to restart it.

### Service Definitions
Services are defined in `/etc/services.d/<service-name>/run`. This is an executable script (often using `execlineb` or `sh`) that launches the process in the foreground.

### Activating Services
To make a service active, it must be symlinked into `/run/s6/services/`. This is usually handled during the image build process:

```dockerfile
# Inside Containerfile
RUN ln -sf /etc/services.d/myapp/run /run/s6/services/myapp/run
```

## Logging

Services usually output their logs to `stdout` and `stderr`, which are captured by Podman. You can view them using:

```bash
podman logs <container-name>
```

## Why s6?

Using an initialization system like [s6](https://skarnet.org/software/s6/) within the container provides several benefits:
- **Zombies**: It properly reaps "zombie" processes.
- **Reliability**: It ensures services are restarted if they fail.
- **Flexibility**: It allows us to run helper processes (like PostgreSQL or nginx) alongside the main application when needed.
- **PUID/PGID**: It allows us to easily drop privileges and run applications as a non-root user (`bsd`) while still performing root-level initialization tasks.
