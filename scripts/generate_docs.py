#!/usr/bin/env python3
import os
import re
import yaml
import jinja2
import pytz
from pathlib import Path

# Paths
SCRIPT_DIR = Path(__file__).parent
TEMPLATE_DIR = SCRIPT_DIR.parent / "templates"
REPO_ROOT = SCRIPT_DIR.parent.parent.parent
DAEMONLESS_IO = REPO_ROOT / "daemonless/daemonless-io"
DOCS_DIR = DAEMONLESS_IO / "docs/images"
PLACEHOLDER_PLUGIN = DAEMONLESS_IO / "placeholder-plugin.yaml"

# Constants
CONFIG_ROOT_VAR = "@CONTAINER_CONFIG_ROOT@"
DEFAULT_CONFIG_ROOT = "/path/to/containers"
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

def update_placeholders(configs):
    if not PLACEHOLDER_PLUGIN.exists():
        return

    with open(PLACEHOLDER_PLUGIN, 'r') as f:
        plugin_data = yaml.safe_load(f) or {}

    # Update Settings for @ syntax
    if "settings" not in plugin_data:
        plugin_data["settings"] = {}
    plugin_data["settings"]["normal_prefix"] = "@"
    plugin_data["settings"]["normal_suffix"] = "@"

    if "placeholders" not in plugin_data:
        plugin_data["placeholders"] = {}

    # Define common validators
    if "validators" not in plugin_data:
        plugin_data["validators"] = {}
    
    plugin_data["validators"]["port_number"] = {
        "name": "Port Number",
        "rules": [
            {
                "regex": "^[0-9]+$",
                "should_match": True,
                "error_message": "Must be a positive integer."
            }
        ]
    }

    # Helper to strip @...@
    def strip_syntax(s):
        return s.strip("@")

    # Pre-populate Global Placeholders
    tz_map = {tz: tz for tz in pytz.common_timezones}
    
    # Config Root
    plugin_data["placeholders"][strip_syntax(CONFIG_ROOT_VAR)] = {
        "default": DEFAULT_CONFIG_ROOT,
        "description": "Container Configuration Root Path",
    }
    
    # Shared Paths
    for path in SHARED_PATHS:
        name = path.strip('/').replace('/', '_').upper()
        plugin_data["placeholders"][f"{name}_PATH"] = {
            "default": f"/path/to{path}",
            "description": f"Global {path} Path"
        }

    # Ensure UTC is top/default if not in list (it usually is)
    plugin_data["placeholders"]["TZ"] = {
        "default": "UTC",
        "description": "Timezone",
        "values": tz_map
    }
    plugin_data["placeholders"]["PUID"] = {
        "default": "1000",
        "description": "User ID",
        "validators": ["port_number"] # Reuse number validator
    }
    plugin_data["placeholders"]["PGID"] = {
        "default": "1000",
        "description": "Group ID",
        "validators": ["port_number"]
    }

    for config in configs:
        # Ports
        if config.get("ports"):
            main_port = config["ports"][0]["port"]
            var_name = f"{config['name'].upper().replace('-', '_')}_PORT"
            
            plugin_data["placeholders"][var_name] = {
                "default": str(main_port),
                "description": f"{config['title']} Host Port",
                "validators": ["port_number"]
            }
            
        # Volumes
        for v in config.get("volumes", []):
            if not v.get("placeholder"): continue
            
            # Skip shared paths as they are pre-populated
            if v['path'] in SHARED_PATHS:
                continue
            
            # Use the relative source path we calculated earlier
            default_path = v.get("source", f"{config['name']}{v['path']}")
            
            # Ensure it doesn't start with / to imply it's relative to Root
            if default_path.startswith("/"):
                default_path = default_path.lstrip("/")
                
            plugin_data["placeholders"][strip_syntax(v["placeholder"])] = {
                "default": default_path,
                "description": f"{config['title']} {v['path']} Path"
            }
            
    # Clean up old SET_ keys if they exist (simple check)
    keys_to_delete = [k for k in plugin_data["placeholders"] if k.startswith("SET_")]
    for k in keys_to_delete:
        del plugin_data["placeholders"][k]

    with open(PLACEHOLDER_PLUGIN, 'w') as f:
        yaml.dump(plugin_data, f, sort_keys=False, default_flow_style=False)
    print("Updated placeholder-plugin.yaml")

def generate_index_page(configs):
    lines = ["# Container Fleet", "", "Explore our collection of high-performance, FreeBSD-native OCI containers.", ""]
    categories = ["Infrastructure", "Network", "Media Management", "Downloaders", "Media Servers", "Databases", "Photos & Media", "Utilities", "Uncategorized"]
    
    by_category = {}
    for config in configs:
        by_category.setdefault(config.get("category", "Uncategorized"), []).append(config)
        
    for cat in categories:
        img_list = by_category.get(cat)
        if not img_list: continue
        lines.extend([f"## {cat}", "", "| Image | Port | Description |", "|-------|------|-------------|"])
        for config in sorted(img_list, key=lambda x: x['title']):
            port_str = "-"
            if config.get("ports"):
                # Use the first port's published number
                port_str = str(config["ports"][0]["port"])
            
            icon = config.get("icon", ":material-docker:")
            if not icon: icon = ":material-docker:"
            
            row = f"| [{icon} {config['title']}]({config['name']}.md) | {port_str} | {config.get('description', '')} |"
            lines.append(row)
        lines.append("")
        
    lines.extend(["## Image Tags", "", "| Tag | Source | Description |", "|-----|--------|-------------|", "| `:latest` | Upstream releases | Newest version from project |", "| `:pkg` | FreeBSD quarterly | Stable, tested in ports |", "| `:pkg-latest` | FreeBSD latest | Rolling package updates |", ""])
    
    (DOCS_DIR / "index.md").write_text("\n".join(lines))
    print("Generated docs/images/index.md")

def update_mkdocs_yaml(configs):
    mkdocs_path = DAEMONLESS_IO / "mkdocs.yaml"
    if not mkdocs_path.exists():
        return
        
    lines = mkdocs_path.read_text().splitlines()
    new_lines, in_images, processed = [], False, False
    
    # Sort configs by Category then Title
    by_cat = {}
    for config in configs:
        cat = config.get("category", "Uncategorized")
        by_cat.setdefault(cat, []).append(config)
        
    for line in lines:
        if line.strip() == "- Images:":
            in_images = True
            if not processed:
                new_lines.extend(["  - Images:", "    - Overview: images/index.md"])
                for cat in sorted(by_cat.keys()):
                    new_lines.append(f"    - {cat}:")
                    # Sort apps in category by Title
                    for config in sorted(by_cat[cat], key=lambda x: x['title']):
                        new_lines.append(f"      - {config['title']}: images/{config['name']}.md")
                processed = True
            continue
        if in_images:
            # Skip existing image entries until we leave the Images block
            # Assuming indented lines belong to Images
            if not line.startswith("    "): 
                # Check if it's a top-level item or another section
                if re.match(r"^  - \w", line) and "Overview:" not in line:
                    in_images = False
                    new_lines.append(line)
        else:
            new_lines.append(line)
            
    with open(mkdocs_path, "w") as f:
        f.write("\n".join(new_lines) + "\n")
    print("Updated mkdocs.yaml")

def load_compose_config(repo_path):
    compose_path = repo_path / "compose.yaml"
    if not compose_path.exists():
        compose_path = repo_path / "compose.yaml"
    
    if not compose_path.exists():
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
    configs = []
    
    # Iterate over repositories
    for repo in REPO_ROOT.glob("daemonless/*"):
        if not repo.is_dir() or repo.name in ["daemonless", "daemonless-io", "cit"]:
            continue
        
        # Priority: compose.yaml -> config.yaml
        config = load_compose_config(repo)
        if not config:
            config = load_config(repo)
            
        if not config:
            # print(f"Skipping {repo.name}: No config found")
            continue
            
        configs.append(config)
        
        # 1. Generate GitHub README.md (Static)
        readme_content = template.render(config, render_mode="github")
        with open(repo / "README.md", "w") as f:
            f.write(readme_content)
        print(f"Generated README.md for {config['name']}")
        
        # 2. Generate MkDocs Page (Dynamic)
        mkdocs_content = template.render(config, render_mode="mkdocs")
        out_path = DOCS_DIR / f"{config['name']}.md"
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with open(out_path, "w") as f:
            f.write(mkdocs_content)
        print(f"Generated docs/images/{config['name']}.md")
        
        # 3. Generate Containerfile (if .j2 exists)
        generate_containerfile(config, repo)

    # 4. Update Placeholders
    update_placeholders(configs)
    
    # 5. Generate Index Page
    generate_index_page(configs)
    
    # 6. Update MkDocs Navigation
    update_mkdocs_yaml(configs)

if __name__ == "__main__":
    main()
