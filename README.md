# Daemonless

Native FreeBSD OCI container images for self-hosted applications.

**No Linux VM required.** Run your containers directly on FreeBSD using Podman + ocijail.

## Features

- **s6 Process Supervision** - Proper signal handling, no zombie processes
- **PUID/PGID Support** - Seamless permission mapping for ZFS datasets and bind mounts
- **Multiple Tags** - Choose between upstream binaries (`:latest`), quarterly packages (`:pkg`), or rolling packages (`:pkg-latest`)
- **Automated CI/CD** - Every image built and tested automatically

## Available Images


### Base

| Image | Port | Description |
|-------|------|-------------|
| [Arr Base](https://github.com/daemonless/arr-base) |  | Shared base image for *Arr applications (Radarr, Sonarr, Lidarr, Prowlarr) containing common dependencies. |
| [FreeBSD Base](https://github.com/daemonless/base) |  | FreeBSD base image with s6 supervision |
| [FreeBSD Base Core](https://github.com/daemonless/base-core) |  | Minimal FreeBSD base image without service supervision. Foundation for CLI tools and non-daemon containers. |
| [Nginx Base](https://github.com/daemonless/nginx-base) |  | Shared base image for Nginx-based applications. |


### Databases

| Image | Port | Description |
|-------|------|-------------|
| [Immich PostgreSQL](https://github.com/daemonless/immich-postgres) |  | PostgreSQL with pgvector and vectorchord extensions required by Immich for vector similarity search. Defaults to PostgreSQL 14 (:latest), PostgreSQL 18 available as :18. |
| [MariaDB](https://github.com/daemonless/mariadb) |  | Drop-in replacement for MySQL built by the original authors — extends core MySQL functionality with alternate storage engines, server optimizations, and patches. |
| [PostgreSQL](https://github.com/daemonless/postgres) |  | The World's Most Advanced Open Source Relational Database on FreeBSD. |
| [Redis](https://github.com/daemonless/redis) |  | Redis key-value store on FreeBSD. |


### Development

| Image | Port | Description |
|-------|------|-------------|
| [Hugo](https://github.com/daemonless/hugo) |  | Fast and flexible static site generator — builds your entire site at creation time rather than on each request. |
| [Zensical](https://github.com/daemonless/zensical) |  | Zensical is a modern static site generator designed to simplify building and maintaining project documentation.  It's built by the creators of Material for MkDocs and shares the same core design principles and philosophy - batteries included, easy to use, with powerful customization options. |
| [code-server](https://github.com/daemonless/code-server) |  | VS Code in the browser — run a full development environment on your FreeBSD server and access it from anywhere. |


### Downloaders

| Image | Port | Description |
|-------|------|-------------|
| [SABnzbd](https://github.com/daemonless/sabnzbd) |  | Free and easy binary newsreader that automates the downloading and processing of Usenet content. |
| [Transmission](https://github.com/daemonless/transmission) |  | Lightweight BitTorrent client with a web UI for managing torrent downloads. |
| [Transmission with WireGuard](https://github.com/daemonless/transmission-wireguard) |  | Transmission BitTorrent client with built-in WireGuard VPN support. |
| [qBittorrent](https://github.com/daemonless/qbittorrent) |  | Fast, stable BitTorrent client with a feature-rich web UI. Supports DHT, PEX, encryption, magnet links, RSS, IP filtering, and remote management. |


### Infrastructure

| Image | Port | Description |
|-------|------|-------------|
| [Authelia](https://github.com/daemonless/authelia-server) |  | Authelia on FreeBSD. |
| [Cloudflared](https://github.com/daemonless/cloudflared) |  | Tunneling daemon that proxies any local webserver through the Cloudflare network without DNS records or firewall changes. |
| [Forgejo](https://github.com/daemonless/forgejo) |  | Forgejo is a self-hosted lightweight software forge |
| [Gitea](https://github.com/daemonless/gitea) |  | Lightweight self-hosted Git service — a community managed fork of Gogs written in Go. |
| [Tailscale](https://github.com/daemonless/tailscale) |  | Zero-config mesh VPN built on WireGuard — securely connect your devices without port forwarding or firewall changes. |
| [Traefik](https://github.com/daemonless/traefik) |  | Modern HTTP reverse proxy and load balancer on FreeBSD. |
| [Woodpecker CI](https://github.com/daemonless/woodpecker) |  | Lightweight CI/CD pipeline server with a built-in agent — integrates with Gitea, GitHub, and GitLab for automated builds and deployments. |
| [lldap](https://github.com/daemonless/lldap) |  | This project is a lightweight authentication server that provides an opinionated, simplified LDAP interface for authentication. |


### Media Management

| Image | Port | Description |
|-------|------|-------------|
| [Bazarr](https://github.com/daemonless/bazarr) |  | Bazarr is a companion application to Sonarr and Radarr. It manages and downloads subtitles based on your requirements. You define your preferences by TV show or movie and Bazarr takes care of everything for you. |
| [BookLore](https://github.com/daemonless/booklore) |  | Self-hosted digital library with smart shelves, metadata, OPDS support, and built-in reader. |
| [Dispatcharr](https://github.com/daemonless/dispatcharr) |  | Dispatcharr — stream dispatching and channel management. |
| [Grimmory](https://github.com/daemonless/grimmory) |  | Self-hosted digital library — successor to BookLore, with smart shelves, metadata, Kobo/KOReader sync, OPDS support, and a built-in reader. |
| [Lidarr](https://github.com/daemonless/lidarr) |  | Music collection manager for Usenet and BitTorrent users — monitors RSS feeds, grabs, sorts, and renames tracks from your favorite artists. |
| [Overseerr](https://github.com/daemonless/overseerr) |  | Media request management for Plex ecosystems. |
| [Prowlarr](https://github.com/daemonless/prowlarr) |  | Indexer manager and proxy for Sonarr, Radarr, and other *arr applications — centralizes indexer configuration across your media stack. |
| [Radarr](https://github.com/daemonless/radarr) |  | Automated movie collection manager that monitors, grabs, and manages your movie library via Usenet and BitTorrent. |
| [ReadMeABook](https://github.com/daemonless/readmeabook) |  | Audiobook request and management platform with AI recommendations. |
| [Seerr](https://github.com/daemonless/seerr) |  | Unified media request management (Plex, Jellyfin, Emby) on FreeBSD. |
| [Sonarr](https://github.com/daemonless/sonarr) |  | Automated TV series collection manager that monitors, grabs, and manages your TV library via Usenet and BitTorrent. |


### Media Servers

| Image | Port | Description |
|-------|------|-------------|
| [Audiobookshelf](https://github.com/daemonless/audiobookshelf) |  | Self-hosted audiobook and podcast server. |
| [Jellyfin](https://github.com/daemonless/jellyfin) |  | Volunteer-built media solution that puts you in control — stream to any device from your own server, with no strings attached. |
| [Plex Media Server](https://github.com/daemonless/plex) |  | Personal media server that organizes and streams your movie, TV, and music collections to all your devices. |
| [Tautulli](https://github.com/daemonless/tautulli) |  | Monitoring and tracking tool for Plex Media Server — tracks what is being watched, who is watching, and when. |


### Network

| Image | Port | Description |
|-------|------|-------------|
| [AdGuard Home](https://github.com/daemonless/adguardhome) |  | Network-wide ad and tracker blocking DNS server. Covers all devices on your network with no client-side software — includes DoH, DoT, DoQ, and a built-in DHCP server. |
| [AdGuardHome Sync](https://github.com/daemonless/adguardhome-sync) |  | Sync AdGuardHome configuration to replica instances. |
| [Samba](https://github.com/daemonless/samba) |  | SMB/CIFS file sharing and Active Directory compatible Domain Controller for FreeBSD. |


### Photos & Media

| Image | Port | Description |
|-------|------|-------------|
| [Immich](https://github.com/daemonless/immich) |  | High performance self-hosted photo and video management solution. |
| [Immich Machine Learning](https://github.com/daemonless/immich-ml) |  | Machine learning service for Immich — handles facial recognition, image classification, and semantic search using ONNX models. |
| [Immich Server](https://github.com/daemonless/immich-server) |  | Self-hosted photo and video backup and management server with web UI, mobile sync, and shared albums. |


### Productivity

| Image | Port | Description |
|-------|------|-------------|
| [AFFiNE](https://github.com/daemonless/affine) |  | AFFiNE is an open-source, privacy-first, local-first knowledge management and collaboration tool. |
| [ONLYOFFICE Document Server](https://github.com/daemonless/onlyoffice) |  | Online office suite providing collaborative editors for documents, spreadsheets, and presentations. Fully compatible with Office Open XML formats (.docx, .xlsx, .pptx). Requires PostgreSQL — see the onlyoffice-postgresql service below. |


### Utilities

| Image | Port | Description |
|-------|------|-------------|
| [Bichon](https://github.com/daemonless/bichon) |  | A lightweight, high-performance Rust email archiver with WebUI. |
| [Heimdall](https://github.com/daemonless/heimdall) |  | An Application dashboard and launcher — organize all your web apps and services in one place. |
| [Home Assistant](https://github.com/daemonless/home-assistant) |  | Open source home automation that puts local control and privacy first. |
| [Homepage](https://github.com/daemonless/homepage) |  | Modern, fully static, fast, secure and highly customizable application dashboard with integrations for over 100 services. |
| [Mealie](https://github.com/daemonless/mealie) |  | Intuitive self-hosted recipe management app designed to be the best recipe management experience on the web. |
| [Nextcloud](https://github.com/daemonless/nextcloud) |  | Online collaboration platform providing groupware capabilities by default, extensible with additional apps. |
| [OpenSpeedTest](https://github.com/daemonless/openspeedtest) |  | Self-hosted HTML5 Network Speed Test on FreeBSD. |
| [Organizr](https://github.com/daemonless/organizr) |  | HTPC/Homelab Services Organizer on FreeBSD. |
| [Paperless-ngx](https://github.com/daemonless/paperless-ngx) |  | A community-supported open-source document management system that transforms your physical documents into a searchable online archive so you can keep, well, less paper. |
| [Playwright](https://github.com/daemonless/playwright) |  | Playwright (Chromium) on FreeBSD. Use as a base image for running browser tests. |
| [SmokePing](https://github.com/daemonless/smokeping) |  | Network latency monitor with historical graphing — tracks round-trip times and packet loss to your hosts over time. |
| [Stirling-PDF](https://github.com/daemonless/stirling-pdf) |  | Locally hosted web application for performing various operations on PDF files — merge, split, compress, convert, OCR, and more. |
| [UniFi Network](https://github.com/daemonless/unifi) |  | Ubiquiti UniFi Network Application for managing UniFi access points, switches, and gateways. |
| [Uptime Kuma](https://github.com/daemonless/uptime-kuma) |  | Self-hosted uptime monitoring tool with a beautiful dashboard, status pages, and multi-channel notifications. |
| [Vaultwarden](https://github.com/daemonless/vaultwarden) |  | Lightweight Bitwarden-compatible password manager server — self-host your passwords, secrets, and secure notes. |
| [n8n](https://github.com/daemonless/n8n) |  | Fair-code workflow automation platform with native AI capabilities — combine visual building with custom code and 400+ integrations. |



## Quick Links

- [Quick Start Guide](https://daemonless.io/quick-start/)
- [Available Images](https://daemonless.io/images/)
- [Documentation](https://daemonless.io)

## Getting Started

```sh
# Pull an image
podman pull ghcr.io/daemonless/radarr:latest

# Run with PUID/PGID mapping
podman run -d --name radarr \
  -e PUID=1000 -e PGID=1000 \
  -v /data/radarr:/config \
  -v /media:/media \
  ghcr.io/daemonless/radarr:latest
```

## License

BSD