# Metadata Labels

The Daemonless project uses container labels to provide structured information about images. These labels power our documentation generator, command generator, and CI/CD pipelines.

## Standard OCI Labels

We follow the [Open Container Initiative (OCI) Image Spec](https://github.com/opencontainers/image-spec/blob/main/annotations.md).

| Label | Description | Example |
|-------|-------------|---------|
| `org.opencontainers.image.title` | Human-readable title of the image. | `"radarr"` |
| `org.opencontainers.image.description` | Short description of what the app does. | `"Radarr movie management"` |
| `org.opencontainers.image.source` | URL to the source code repo. | `"https://github.com/daemonless/radarr"` |
| `org.opencontainers.image.url` | URL to the application's website. | `"https://radarr.video/"` |
| `org.opencontainers.image.licenses` | The license(s) of the application. | `"GPL-3.0-only"` |
| `org.opencontainers.image.vendor` | Organization responsible for the image. | `"daemonless"` |

## Daemonless Custom Labels (`io.daemonless.*`)

These labels provide technical metadata used by our automated tools.

| Label | Description | Example |
|-------|-------------|---------|
| `io.daemonless.port` | The primary port(s) used by the app (comma-separated). | `"7878"` or `"80,443"` |
| `io.daemonless.arch` | Supported CPU architectures (comma-separated). | `"amd64,arm64"` |
| `io.daemonless.volumes` | Default volumes the app expects (comma-separated). | `"/movies,/downloads"` |
| `io.daemonless.config-mount` | The internal path for the config directory. Defaults to `/config`. | `"/gitea"` |
| `io.daemonless.pkg-source` | Set to `"containerfile"` if the main Containerfile should be used for `:pkg` builds. | `"containerfile"` |
| `io.daemonless.base` | Specifies a specialized base image requirement. | `"nginx"` |
| `io.daemonless.network` | Specifies a required networking mode. | `"host"` |
| `io.daemonless.wip` | Set to `"true"` to disable the image in CI/CD pipelines. | `"true"` |

## Why Labels Matter

1.  **Command Generator:** The [Interactive Tool](https://daemonless.github.io/daemonless/) reads these labels to automatically populate ports, volumes, and annotations in the generated `podman run` commands.
2.  **Documentation:** The `generate-docs.sh` script extracts this data to build our image index.
3.  **CI/CD:** Pipelines use labels like `io.daemonless.wip` to determine which images are ready for production builds.

## Guidelines for Contributors

When adding a new image, ensure all standard OCI labels are present and provide at least the `io.daemonless.port` and `io.daemonless.arch` custom labels.
