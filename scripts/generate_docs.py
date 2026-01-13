#!/usr/bin/env python3
"""
Generate README.md and Containerfiles for daemonless repos.
MkDocs site generation is handled by daemonless-io/scripts/generate_docs.py
"""
import yaml
import jinja2
from pathlib import Path

# Paths
SCRIPT_DIR = Path(__file__).parent
TEMPLATE_DIR = SCRIPT_DIR.parent / "templates"
REPO_ROOT = SCRIPT_DIR.parent.parent.parent

# Constants
CONFIG_ROOT_VAR = "@CONTAINER_CONFIG_ROOT@"
SHARED_PATHS = ["/downloads", "/movies", "/tv", "/music", "/books", "/media", "/data"]

# Load Template
env = jinja2.Environment(loader=jinja2.FileSystemLoader(TEMPLATE_DIR))
template = env.get_template("README.j2")

def get_tags(repo_path):
    tags = ["latest"]
    if (repo_path / "Containerfile.pkg").exists():
        tags.extend(["pkg", "pkg-latest"])
    return tags

def load_config(repo_path):
    config_path = repo_path / ".daemonless" / "config.yaml"
    if not config_path.exists():
        print(f"Skipping {repo_path.name}: No .daemonless/config.yaml")
        return None
    
    with open(config_path, "r") as f:
        data = yaml.safe_load(f)
    
    # Add calculated fields
    data["name"] = repo_path.name
    data["title"] = data.get("title", repo_path.name.title())
    data["repo_url"] = f"https://github.com/daemonless/{repo_path.name}"
    data["tags"] = get_tags(repo_path)
    data["upstream_binary"] = data.get("upstream_binary", True)
    # data["root_var"] is now per-volume
    
    # Ensure lists exist
    data.setdefault("ports", [])
    data.setdefault("env", [])
    data.setdefault("volumes", [])
    
    # Enrich Env
    for e in data['env']:
        if e['name'] in ["PUID", "PGID", "TZ"]:
            e['placeholder'] = f"@{e['name']}@"
            
    # Enrich Volumes
    for v in data['volumes']:
        tgt = v['path']
        clean_target = tgt.strip('/').replace('/', '_').upper()
        
        # Determine source path & placeholder
        if tgt in SHARED_PATHS:
            v['placeholder'] = f"@{clean_target}_PATH@"
            v['root_var'] = None # No prefix for global shared paths
            v['source'] = tgt.lstrip('/')
        elif tgt == "/config":
            # Special case: /config maps to app_name (e.g. radarr:/config)
            v['placeholder'] = f"@{data['name'].upper().replace('-', '_')}_CONFIG_PATH@"
            v['root_var'] = CONFIG_ROOT_VAR
            v['source'] = data['name']
        else:
            v['placeholder'] = f"@{data['name'].upper().replace('-', '_')}_{clean_target}_PATH@"
            v['root_var'] = CONFIG_ROOT_VAR
            v['source'] = f"{data['name']}{tgt}"
    
    return data

def load_compose_config(repo_path):
    # Check compose.yaml first, then container-compose.yml for stacks
    compose_path = None
    for name in ["compose.yaml", "container-compose.yml"]:
        candidate = repo_path / name
        if candidate.exists():
            compose_path = candidate
            break

    if not compose_path:
        return None
    
    with open(compose_path, "r") as f:
        data = yaml.safe_load(f)
    
    if not data or 'services' not in data:
        return None
        
    # Handle base images or configs without services
    if not data['services']:
        config = {
            'name': repo_path.name,
            'title': data.get('x-daemonless', {}).get('title', repo_path.name.title()),
            'description': data.get('x-daemonless', {}).get('description', ''),
            'category': data.get('x-daemonless', {}).get('category', 'Uncategorized'),
            'upstream_url': data.get('x-daemonless', {}).get('upstream_url', ''),
            'web_url': data.get('x-daemonless', {}).get('web_url', ''),
            'freshports_url': data.get('x-daemonless', {}).get('freshports_url', ''),
            'user': data.get('x-daemonless', {}).get('user', 'root'),
            'mlock': data.get('x-daemonless', {}).get('mlock', False),
            'upstream_binary': data.get('x-daemonless', {}).get('upstream_binary', True),
            'icon': data.get('x-daemonless', {}).get('icon', None),
            'healthcheck': None,
            'env': [],
            'volumes': [],
            'ports': []
        }
        config.setdefault("repo_url", f"https://github.com/daemonless/{repo_path.name}")
        config["tags"] = get_tags(repo_path)
        return config

    # Assume single service for now or take the first one
    service_name = list(data['services'].keys())[0]
    service = data['services'][service_name]
    meta = data.get('x-daemonless', {})
    docs = meta.get('docs', {})
    
    config = {
        'name': repo_path.name,
        'title': meta.get('title', repo_path.name.title()),
        'description': meta.get('description', ''),
        'category': meta.get('category', 'Uncategorized'),
        'upstream_url': meta.get('upstream_url', ''),
        'web_url': meta.get('web_url', ''),
        'freshports_url': meta.get('freshports_url', ''),
        'user': meta.get('user', 'root'),
        'mlock': meta.get('mlock', False),
        'upstream_binary': meta.get('upstream_binary', True),
        'icon': meta.get('icon', None),
        'healthcheck': meta.get('healthcheck', None), # Could parse from service.healthcheck too
        'env': [],
        'volumes': [],
        'ports': []
    }

    # Parse Environment
    env_docs = {str(k): v for k, v in docs.get('env', {}).items()}
    env_vars = service.get('environment', [])
    if isinstance(env_vars, dict):
        env_items = env_vars.items()
    else:
        # Handle list ["KEY=VAL"]
        env_items = [e.split('=', 1) for e in env_vars]
    
    for key, val in env_items:
        # Determine a safe display value for empty vars
        display_val = val
        if not val or val == '""' or val == "''":
            if any(x in key.upper() for x in ["PASS", "KEY", "SECRET", "TOKEN"]):
                display_val = f"<{key.upper()}>"
            else:
                display_val = ""

        item = {
            'name': key,
            'default': display_val,
            'desc': env_docs.get(str(key), '')
        }
        
        # Only these are allowed as interactive website placeholders
        if key in ["PUID", "PGID", "TZ"]:
            item['placeholder'] = f"@{key}@"
            
        config['env'].append(item)

    # Parse Volumes
    vol_docs = {str(k): v for k, v in docs.get('volumes', {}).items()}
    for vol in service.get('volumes', []):
        if isinstance(vol, str):
            src, tgt = vol.split(':')[0], vol.split(':')[1]
        else:
            src, tgt = vol.get('source'), vol.get('target')
        
        # Calculate placeholder name
        # Calculate placeholder name
        # /config -> CONFIG
        # /var/lib/data -> VAR_LIB_DATA
        clean_target = tgt.strip('/').replace('/', '_').upper()
        
        # Clean path for doc purposes (remove . or ./ if source)
        # But for 'path' in doc table, we want the TARGET (container path)
        vol_info = vol_docs.get(str(tgt), '')
        desc = ""
        optional = False
        
        if isinstance(vol_info, dict):
            desc = vol_info.get('desc', '')
            optional = vol_info.get('optional', False)
        else:
            desc = str(vol_info)
            
        # Determine source path
        # SHARED_PATHS defined globally at top level now
        if tgt in SHARED_PATHS:
            source_path = tgt.lstrip('/')
            placeholder = f"@{clean_target}_PATH@"
            root_var = None
        elif tgt == "/config":
             # Special case: /config maps to app_name (e.g. radarr:/config)
            placeholder = f"@{config['name'].upper().replace('-', '_')}_CONFIG_PATH@"
            source_path = config['name']
            root_var = CONFIG_ROOT_VAR
        else:
            source_path = f"{config['name']}{tgt}"
            root_var = CONFIG_ROOT_VAR
            # Standard placeholder
            placeholder = f"@{config['name'].upper().replace('-', '_')}_{clean_target}_PATH@"

        config['volumes'].append({
            'path': tgt,
            'desc': desc,
            'optional': optional,
            'placeholder': placeholder,
            'source': source_path,
            'root_var': root_var
        })

    # Parse Ports
    port_docs = {str(k): v for k, v in docs.get('ports', {}).items()}
    for port in service.get('ports', []):
        if isinstance(port, str):
            pub, tgt = port.split(':')[0], port.split(':')[1]
            proto = 'tcp'
        else:
            pub, tgt = port.get('published'), port.get('target')
            proto = port.get('protocol', 'tcp')
        
        config['ports'].append({
            'port': pub,
            'protocol': proto,
            'desc': port_docs.get(str(pub), ''), # Use published port as key
            'name': 'web' # Defaulting
        })
        
    # Ensure lists exist (redundant but safe)
    config.setdefault("ports", [])
    config.setdefault("env", [])
    config.setdefault("volumes", [])
    config.setdefault("repo_url", f"https://github.com/daemonless/{repo_path.name}")
    config["tags"] = get_tags(repo_path)
    # config["root_var"] Removed as it's now per-volume
    
    return config

def generate_containerfile(config, repo_path):
    # Main Containerfile
    template_path = repo_path / "Containerfile.j2"
    if template_path.exists():
        repo_env = jinja2.Environment(loader=jinja2.FileSystemLoader(repo_path))
        template = repo_env.get_template("Containerfile.j2")
        content = template.render(config)
        with open(repo_path / "Containerfile", "w") as f:
            f.write(content)
        print(f"Generated Containerfile for {config['name']}")

    # Containerfile.pkg
    pkg_template_path = repo_path / "Containerfile.pkg.j2"
    if pkg_template_path.exists():
        repo_env = jinja2.Environment(loader=jinja2.FileSystemLoader(repo_path))
        template = repo_env.get_template("Containerfile.pkg.j2")
        content = template.render(config)
        with open(repo_path / "Containerfile.pkg", "w") as f:
            f.write(content)
        print(f"Generated Containerfile.pkg for {config['name']}")

def main():
    # Iterate over repositories
    for repo in REPO_ROOT.glob("daemonless/*"):
        if not repo.is_dir() or repo.name in ["daemonless", "daemonless-io", "cit", "freebsd-ports"]:
            continue

        # Priority: compose.yaml -> config.yaml
        config = load_compose_config(repo)
        if not config:
            config = load_config(repo)

        if not config:
            continue

        # 1. Generate GitHub README.md
        readme_content = template.render(config, render_mode="github")
        with open(repo / "README.md", "w") as f:
            f.write(readme_content)
        print(f"Generated README.md for {config['name']}")

        # 2. Generate Containerfile (if .j2 exists)
        generate_containerfile(config, repo)

if __name__ == "__main__":
    main()
