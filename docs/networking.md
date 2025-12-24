# Networking Guide

FreeBSD Podman containers can use several different networking modes. Understanding which one to use is critical for connectivity and performance.

## 1. Bridge Networking (Default)

This is the most common mode. The container gets its own IP address on a virtual network (usually `10.88.0.0/16`).

### Port Forwarding
To access services from your host or network, you must map ports using the `-p` flag. 

**Requirement:** This requires `pf` (Packet Filter) configuration on your FreeBSD host to handle the NAT/Redirection.

**Example:**
```bash
podman run -d --name radarr -p 7878:7878 ghcr.io/daemonless/radarr:latest
```

### Host Configuration for Bridge
Add these lines to your `/etc/pf.conf`:

```
# Podman container networking
rdr-anchor "cni-rdr/*"
nat-anchor "cni-rdr/*"
table <cni-nat>
nat on $ext_if inet from <cni-nat> to any -> ($ext_if)
nat on $ext_if inet from 10.88.0.0/16 to any -> ($ext_if)
```

And enable local filtering:
```bash
sysctl net.pf.filter_local=1
```

## 2. Host Networking

In this mode, the container shares the host's network stack directly. It does not get its own IP address.

### Use Case
- When the application needs to perform L2 network discovery (e.g., UniFi adopting APs, SmokePing monitoring local devices).
- When you want to avoid the overhead of NAT.

**Example:**
```bash
podman run -d --name unifi --network host ghcr.io/daemonless/unifi:latest
```

**Note:** Port mapping (`-p`) has no effect in this mode; the application listens on the host IP directly.

## 3. VNET (Virtual Network Stack)

VNET provides a private, isolated network stack for the jail. 

### Use Case
- Required for applications that need to manage their own network interfaces or routing tables (e.g., WireGuard, Gitea).
- Higher isolation than bridge mode.

**Example:**
```bash
podman run -d --name gitea --annotation 'org.freebsd.jail.vnet=new' ghcr.io/daemonless/gitea:latest
```

### Limitations
- **Port Forwarding:** Standard `-p` mapping is currently not supported by stock `ocijail` when VNET is enabled. You must access the container via its internal IP address (e.g., `10.88.0.x`).
- **Kernel Support:** Requires a kernel built with VNET support (default in FreeBSD 13+).

## Comparison Summary

| Feature | Bridge (Default) | Host | VNET |
|---------|------------------|------|------|
| **IP Address** | Private (10.88.x.x) | Shared with Host | Private (10.88.x.x) |
| **Port Mapping** | Supported (`-p`) | Not needed | Not supported |
| **Isolation** | High | Low | Very High |
| **Best For** | Most Apps | Network Discovery | VPNs / High Isolation |
| **pf Required** | Yes | No | Yes |
