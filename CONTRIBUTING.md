# Contributing to Daemonless

A 10-minute guide to building and testing your first FreeBSD container image.

## Prerequisites

- **FreeBSD** (physical host or VM with Podman access)
- **Python 3.11+** and **git**
- **Podman** with **ocijail 0.5.0+** runtime (`pkg install ocijail`)
- A GitHub account (for forking and PRs)

Not sure if your environment is ready? After installing dbuild, run:

```bash
dbuild ci-test-env
```

This checks for all required tools, networking, and jail support.

## Setup (~5 minutes)

### 1. Clone the repos

```bash
# The main project (scripts, docs, version tracking)
git clone https://github.com/daemonless/daemonless

# The build tool
git clone https://github.com/daemonless/dbuild

# An image repo to use as a reference
git clone https://github.com/daemonless/tautulli
```

### 2. Install dependencies

```bash
# Core build tools
pkg install podman buildah skopeo jq trivy py311-pyyaml

# Optional: for screenshot-based visual regression testing
pkg install chromium py311-selenium py311-scikit-image
```

### 3. Install dbuild

```bash
cd dbuild
make install
```

Or manually:

```bash
pkg install py311-pyyaml
export PYTHONPATH=/path/to/dbuild
alias dbuild='python3 -m dbuild'
```

Alternatively, you can install via pip:

```bash
cd dbuild
pip install .
```

### 3. Verify your environment

```bash
dbuild ci-test-env
```

All required checks should pass. Optional tools (like podman-compose) are only needed for multi-service stacks.

## Your First Image (~5 minutes)

### 1. Scaffold a new image

```bash
mkdir myapp && cd myapp
git init
dbuild init
```

This creates:

```
myapp/
├── Containerfile           # Build from upstream binaries (:latest tag)
├── Containerfile.pkg       # Build from FreeBSD packages (:pkg tag)
├── .daemonless/
│   └── config.yaml         # Build + test configuration
├── .woodpecker.yaml        # CI/CD pipeline (or .github/workflows/)
└── root/                   # Files copied into container
    └── etc/
        ├── cont-init.d/    # Initialization scripts
        └── services.d/     # s6 service definitions
            └── myapp/
                └── run     # Service start script
```

### 2. Build it

```bash
dbuild build
```

### 3. Test it

```bash
dbuild test
```

### 4. Run it manually

```bash
podman run -d --name myapp \
  -p 8080:8080 \
  -e PUID=1000 -e PGID=1000 \
  -v /tmp/myapp-config:/config \
  localhost/myapp:build-latest
```

## Contribution Types

| Type | Description | Where |
|------|-------------|-------|
| **New images** | Package a new application as a FreeBSD container | New repo under `daemonless/` |
| **Image fixes** | Bug fixes or improvements to existing images | The image's repo |
| **Tooling** | Improvements to dbuild or CIT | `daemonless/dbuild` |
| **Documentation** | Guides, corrections, image docs | `daemonless/daemonless-io` |

## Image Checklist

Before submitting a new image, verify:

- [ ] `compose.yaml` declares public metadata, documented env vars, volumes, ports, and deployment examples
- [ ] `Containerfile*.j2` defines image construction and renders public labels from context
- [ ] `dbuild generate` has refreshed generated `Containerfile*` and `README.md` artifacts
- [ ] `root/etc/services.d/<app>/run` — s6 service script using `s6-setuidgid bsd`
- [ ] `.daemonless/config.yaml` defines build variants and CIT test configuration
- [ ] CI pipeline configured (`.woodpecker.yaml` or `.github/workflows/`)
- [ ] Upstream license verified — check the SPDX identifier at https://spdx.org/licenses/
- [ ] `dbuild build && dbuild test` passes locally

## Conventions

### Source ownership

Three editable sources, three questions: `compose.yaml` **declares** the app
contract (what users see and deploy), `.daemonless/config.yaml` **operates** the
build/test automation, and `Containerfile*.j2` **constructs** the image.
Generated `Containerfile*` and `README.md` are artifacts — change the source and
run `dbuild generate`.

For the full breakdown of which file owns what (ports, health, annotations,
labels), see [Service Source Files](https://daemonless.io/guides/service-anatomy/).

### Containerfile rules

- Use `fetch`, not `curl` — FreeBSD base includes `fetch`
- Clean the pkg cache: `pkg clean -ay && rm -rf /var/cache/pkg/*`
- Set ownership: `chown -R bsd:bsd /config /app`
- Use `ARG` for `BASE_VERSION`, `PACKAGES`, and `VERSION`
- Render public labels from `compose.yaml` context; keep variant/build labels in templates

### Runtime conventions

- Run services as `bsd` user via `s6-setuidgid bsd`
- Support `PUID`, `PGID`, and `TZ` environment variables
- Use `/config` as the configuration volume
- Use `exec` in run scripts for proper signal handling

### Labels

Every image still emits `io.daemonless.*` and OCI labels, but public label values should be generated from `compose.yaml` metadata instead of copied by hand into generated Containerfiles. Template-owned build labels such as package source, package name, upstream extraction details, and work-in-progress status may remain in `Containerfile*.j2`.

See the [Development Guide](https://daemonless.io/guides/development/) for the full labels reference.

## Testing

All images must pass CIT (Container Integration Testing) before push. CIT has four cumulative modes:

| Mode | Checks | Use case |
|------|--------|----------|
| `shell` | Container starts, exec works | Base images, CLI tools |
| `port` | Shell + TCP port listening | Network services |
| `health` | Port + HTTP endpoint responds | Web apps |
| `screenshot` | Health + visual regression | Web UIs |

Configure your test mode in `.daemonless/config.yaml`:

```yaml
cit:
  mode: health
  port: 8080
  health: /api/health
```

Run tests locally:

```bash
dbuild build && dbuild test
```

## LLM / AI Policy

If your contribution is aided by LLMs or other AI tools, please read our [LLM / AI Contribution Policy](LLM_POLICY.md). You are 100% responsible for your submissions, and AI-generated text is not permitted in pull requests or issues.

## Submitting Changes

1. **Fork** the image repo on GitHub
2. **Branch** from `main`
3. **Build and test** locally with `dbuild build && dbuild test`
4. **Open a PR** — CI runs CIT automatically
5. All CIT gates must pass before merge

## Get Help

Stuck on something? Join us on [Discord](https://discord.gg/PTg5DJ2y) — it's the fastest way to get help from the community.

## Further Reading

- [Development Guide](https://daemonless.io/guides/development/) — Full architecture, labels reference, Containerfile patterns
- [dbuild](https://daemonless.io/guides/dbuild/) — Complete build engine documentation
- [Quality Gates (CIT)](https://daemonless.io/guides/cit/) — Test modes, configuration, visual regression
- [CI/CD Pipeline](https://daemonless.io/guides/ci-cd/) — CI integration and pipeline details
- [Image Tagging](https://daemonless.io/guides/tagging/) — Tag conventions and version strategy
- [OCI Compliance](https://daemonless.io/guides/oci-compliance/) — Label standards and SBOM
