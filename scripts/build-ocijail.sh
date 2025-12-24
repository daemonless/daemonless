#!/bin/sh
# Build patched ocijail with allow.* annotation support
#
# This script prioritizes using the FreeBSD ports tree if available,
# falling back to a direct git clone and bazel build otherwise.
#
# Usage: ./build-ocijail.sh
#

set -e

# --- Configuration ---
OCIJAIL_REPO="https://github.com/dfr/ocijail.git"
PORTS_PATH="/usr/ports/sysutils/ocijail"

# --- Embedded Patch ---
# This patch works for both the 0.4.0 port and the latest git main.
PATCH_CONTENT='
--- ocijail/create.cpp.orig
+++ ocijail/create.cpp
@@ -214,6 +214,7 @@
     // Get the parent jail name and requested vnet type (if any)
     std::optional<std::string> parent_jail;
     auto vnet = jail::INHERIT;
+    std::vector<std::string> allow_params;
     if (config.contains("annotations")) {
         auto config_annotations = config["annotations"];
         if (config_annotations.contains("org.freebsd.parentJail")) {
@@ -232,6 +233,20 @@
                     "bad value for org.freebsd.jail.vnet: " + val);
             }
         }
+
+        // Check for allow.* annotations (e.g., org.freebsd.jail.allow.mlock)
+        const std::string allow_prefix = "org.freebsd.jail.allow.";
+        for (auto& [key, value] : config_annotations.items()) {
+            if (key.rfind(allow_prefix, 0) == 0) {
+                std::string param = "allow." + key.substr(allow_prefix.length());
+                if (value.is_string()) {
+                    std::string val = value;
+                    if (val == "true" || val == "1") {
+                        allow_params.push_back(param);
+                    }
+                }
+            }
+        }
     }
 
     // Create a jail config from the OCI config
@@ -247,6 +262,10 @@
     if (allow_chflags) {
         jconf.set("allow.chflags");
     }
+    // Set additional allow parameters from annotations
+    for (const auto& param : allow_params) {
+        jconf.set(param);
+    }
     if (root_readonly) {
         jconf.set("path", readonly_root_path);
     } else {
'

# --- Functions ---

log_info() {
    echo ">> $1"
}

log_error() {
    echo "!! $1" >&2
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root (or with doas/sudo) to install."
        exit 1
    fi
}

# --- Main ---

check_root

# Create secure temp directory
WORK_DIR=$(mktemp -d -t ocijail_build)
log_info "Created temporary build directory: $WORK_DIR"

# Cleanup on exit
cleanup() {
    if [ -d "$WORK_DIR" ]; then
        log_info "Cleaning up $WORK_DIR..."
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT INT TERM

if [ -d "$PORTS_PATH" ]; then
    log_info "Ports tree found at $PORTS_PATH. Using Port Overlay method."
    
    # Copy port to our work dir
    cp -R "$PORTS_PATH/" "$WORK_DIR/"
    cd "$WORK_DIR"

    # Ensure files directory exists
    mkdir -p files

    # Inject our patch
    log_info "Injecting Daemonless patch into port..."
    echo "$PATCH_CONTENT" > files/patch-daemonless-annotations

    # Build and install using ports framework
    log_info "Running 'make reinstall' (this will install dependencies and build)..."
    # We use BATCH=yes to avoid interactive prompts
    make reinstall BATCH=yes CLEAN_DEPENDS=yes clean

else
    log_info "Ports tree not found. Falling back to Git + Bazel method."
    
    # Install build dependencies
    log_info "Installing build dependencies (bazel, git)..."
    pkg install -y bazel git

    cd "$WORK_DIR"
    log_info "Cloning ocijail from $OCIJAIL_REPO..."
    git clone --depth 1 "$OCIJAIL_REPO" .

    log_info "Applying patch..."
    if echo "$PATCH_CONTENT" | patch -p0; then
        log_info "Patch applied successfully."
    else
        log_error "Failed to apply patch."
        exit 1
    fi

    log_info "Building ocijail with Bazel (this may take a while)..."
    # Set HOME to avoid Bazel cache permission issues
    export HOME=/root
    bazel build //ocijail

    if [ ! -f "bazel-bin/ocijail/ocijail" ]; then
        log_error "Build failed. Binary not found."
        exit 1
    fi

    log_info "Installing to /usr/local/bin/ocijail..."
    cp /usr/local/bin/ocijail /usr/local/bin/ocijail.orig 2>/dev/null || true
    cp bazel-bin/ocijail/ocijail /usr/local/bin/ocijail
    chmod 755 /usr/local/bin/ocijail
fi

log_info "Done! Patched ocijail is installed."
log_info "Version: $(ocijail --version 2>/dev/null || echo 'unknown')"
