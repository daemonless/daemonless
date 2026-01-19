#!/usr/bin/env python3

import os
import json
import subprocess
import glob
import sys
import datetime
import re
import urllib.request
import urllib.error

# Configuration
ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PARENT_DIR = os.path.dirname(ROOT_DIR)  # src/daemonless
OUTPUT_FILE = os.path.join(ROOT_DIR, "daemonless-versions.json")

def run_command(cmd):
    try:
        result = subprocess.run(cmd, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None

def get_pkg_version(pkg_name, repo_type="latest"):
    """
    Query pkg version.
    repo_type: 'quarterly' or 'latest'
    """
    if not pkg_name:
        return None
    
    repo_flag = ""
    if repo_type == "quarterly":
        repo_flag = "-r FreeBSD-quarterly"
    else:
        repo_flag = "-r FreeBSD"

    # 1. Try local pkg command (FreeBSD native)
    try:
        cmd = f"pkg rquery {repo_flag} '%v' {pkg_name} 2>/dev/null"
        ver = run_command(cmd)
        if ver:
            return ver
    except Exception:
        pass
        
    # 2. Fallback: SSH to saturn (FreeBSD host)
    # Check if we can ssh to saturn (simple check once could be better, but let's just try)
    try:
        # We need to escape the repo_flag and query properly for the shell
        ssh_cmd = f"ssh -o BatchMode=yes -o ConnectTimeout=5 saturn \"pkg rquery {repo_flag} '%v' {pkg_name}\""
        ver = run_command(ssh_cmd)
        if ver:
             return ver
    except Exception:
        pass

    # 3. Fallback: Podman on Linux
    # Check if podman is available
    if os.path.exists("/usr/bin/podman") or os.path.exists("/usr/local/bin/podman"):
        image = "ghcr.io/daemonless/base:15"
        # We use -U to ensure we have data (since ephemeral container has empty /var/db/pkg)
        podman_cmd = f"podman run --rm {image} pkg rquery -U {repo_flag} '%v' {pkg_name}"
        
        try:
            result = subprocess.run(podman_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            if result.returncode == 0:
                return result.stdout.strip()
        except Exception:
            pass

    return None

    return None

def get_github_token():
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        return token
    # Try gh cli
    try:
        return run_command("gh auth token")
    except Exception:
        return None

def fetch_url(url):
    try:
        headers = {'User-Agent': 'daemonless/1.0'}
        if "api.github.com" in url:
            token = get_github_token()
            if token:
                headers['Authorization'] = f'token {token}'
        
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req) as response:
            return response.read().decode('utf-8')
    except urllib.error.HTTPError as e:
        if e.code == 403:
            print(f"Rate limit exceeded for {url}", file=sys.stderr)
        else:
            print(f"HTTP Error {e.code} fetching {url}: {e}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Error fetching {url}: {e}", file=sys.stderr)
        return None

def resolve_vars(text, vars_dict):
    """Recursively resolve ${VAR} in text using vars_dict."""
    if not text:
        return text
    # Simple regex for ${VAR}
    pattern = re.compile(r'\$\{([a-zA-Z0-9_]+)\}')
    
    # Avoid infinite loops with a max_depth
    for _ in range(5):
        match = pattern.search(text)
        if not match:
            break
        var_name = match.group(1)
        val = vars_dict.get(var_name, "")
        text = text.replace(f"${{{var_name}}}", val)
    return text

def parse_containerfile(filepath):
    """
    Parse Containerfile to extract ARGs and LABELs.
    Returns a dict with 'envs' (arg values) and 'labels'.
    """
    envs = {}
    labels = {}
    
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
            
        for line in lines:
            line = line.strip()
            if line.startswith("ARG "):
                content = line[4:].strip()
                if "=" in content:
                    key, val = content.split("=", 1)
                    key = key.strip()
                    val = val.strip()
                    
                    # Handle quoting
                    if val.startswith('"') and val.endswith('"'):
                        val = val[1:-1].replace(r'\"', '"')
                    elif val.startswith("'") and val.endswith("'"):
                        val = val[1:-1]

                    val = resolve_vars(val, envs)
                    envs[key] = val
                    
        # Robust label finding
        content = "".join(lines).replace("\\\n", " ") 
        
        def find_label(name):
            # match keys with values in:
            # 1. Double quotes (allowing escaped quotes inside)
            # 2. Single quotes
            # 3. Bare words
            pattern = re.compile(
                rf"{re.escape(name)}\s*=\s*(?:\"((?:[^\"]|\\.)*)\"|'([^']*)'|([^\s]*))"
            )
            msg = pattern.search(content)
            if msg:
                # Group 1: Double quoted (may have escapes)
                # Group 2: Single quoted
                # Group 3: Bare
                if msg.group(1) is not None:
                    raw_val = msg.group(1).replace(r'\"', '"')
                elif msg.group(2) is not None:
                    raw_val = msg.group(2)
                else:
                    raw_val = msg.group(3)
                    
                return resolve_vars(raw_val, envs)
            return None

        labels["upstream-url"] = find_label("io.daemonless.upstream-url")
        labels["upstream-jq"] = find_label("io.daemonless.upstream-jq")
        labels["pkg-name"] = find_label("io.daemonless.pkg-name")
        
        # Fallback for ARG PKG_NAME if label missing
        if not labels["pkg-name"]:
            labels["pkg-name"] = envs.get("PKG_NAME")
            
        return labels

    except Exception as e:
        print(f"Error parsing {filepath}: {e}", file=sys.stderr)
        return {}

def process_service(service_path):
    service_name = os.path.basename(service_path)
    
    # 1. Parse Containerfile (preferred) or Containerfile.pkg
    cf_path = os.path.join(service_path, "Containerfile")
    if not os.path.exists(cf_path):
        cf_path = os.path.join(service_path, "Containerfile.pkg")
        
    if not os.path.exists(cf_path):
        return None

    info = parse_containerfile(cf_path)
    pkg_name = info.get("pkg-name")
    upstream_url = info.get("upstream-url")
    upstream_jq = info.get("upstream-jq")
    
    # Fallback: if pkg_name not found but Containerfile.pkg exists, assume service_name or parse that file specifically
    if not pkg_name and os.path.exists(os.path.join(service_path, "Containerfile.pkg")):
         pkg_info = parse_containerfile(os.path.join(service_path, "Containerfile.pkg"))
         pkg_name = pkg_info.get("pkg-name") or service_name

    result = {}
    
    # 1. Get PKG versions
    if pkg_name:
        q_ver = get_pkg_version(pkg_name, "quarterly")
        l_ver = get_pkg_version(pkg_name, "latest")
        
        if q_ver:
            result["pkg"] = q_ver
        if l_ver:
            result["pkg-latest"] = l_ver

    # 2. Get Upstream version
    if upstream_url and upstream_jq:
        content = fetch_url(upstream_url)
        if content:
            try:
                # Use system jq
                jq_cmd = ["jq", "-r", upstream_jq]
                jq_proc = subprocess.Popen(jq_cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                out, err = jq_proc.communicate(input=content)
                if jq_proc.returncode == 0:
                    val = out.strip()
                    if val and val != "null":
                        result["upstream"] = val
                else:
                    print(f"jq error for {service_name}: {err}", file=sys.stderr)
            except Exception as e:
                print(f"Error running jq for {service_name}: {e}", file=sys.stderr)

    if not result:
        return None
        
    return {service_name: result}

def main():
    services = {}
    
    # Scan directories
    services_dir = os.environ.get("SERVICES_DIR")
    if services_dir:
        scan_root = os.path.abspath(services_dir)
    else:
        scan_root = PARENT_DIR

    print(f"Scanning directories in: {scan_root}", file=sys.stderr)
    
    dirs_to_scan = sorted(glob.glob(os.path.join(scan_root, "*")))
    print(f"Found {len(dirs_to_scan)} candidates.", file=sys.stderr)
    
    for d in dirs_to_scan:
        if not os.path.isdir(d):
            continue
        name = os.path.basename(d)
        if name in [".git", ".github", "scripts", "daemonless", "ahze.lan", "ahze.net"]: 
            continue
            
        print(f"Checking {name}...", file=sys.stderr)
        
        if (os.path.exists(os.path.join(d, "Containerfile")) or 
            os.path.exists(os.path.join(d, "Containerfile.pkg"))):
            res = process_service(d)
            if res:
                services.update(res)
        else:
            print(f"  No Containerfile found in {name}", file=sys.stderr)

    output = {
        "last_check": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
        "services": services
    }
    
    print(json.dumps(output, indent=2, sort_keys=True))

if __name__ == "__main__":
    main()
