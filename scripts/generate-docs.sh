#!/bin/sh
# Generate docs/index.html from Containerfile labels
# Run from daemonless root: ./scripts/generate-docs.sh

set -e

SCRIPT_DIR=$(dirname "$0")
ROOT_DIR="${SCRIPT_DIR}/.."
IMAGES_DIR="${ROOT_DIR}/images"
OUTPUT="${ROOT_DIR}/docs/index.html"

# Create docs dir if needed
mkdir -p "${ROOT_DIR}/docs"

# Extract image data from Containerfiles
extract_images() {
    for dir in "${IMAGES_DIR}"/*/; do
        [ -d "$dir" ] || continue
        name=$(basename "$dir")
        cf="${dir}Containerfile"
        [ -f "$cf" ] || continue

        # Extract labels
        title=$(grep 'org.opencontainers.image.title\s*=' "$cf" | sed 's/.*title\s*=\s*"\([^"]*\)".*/\1/' | head -1)
        desc=$(grep 'org.opencontainers.image.description\s*=' "$cf" | sed 's/.*description\s*=\s*"\([^"]*\)".*/\1/' | head -1)
        port=$(grep 'io.daemonless.port\s*=' "$cf" | sed 's/.*port\s*=\s*"\([^"]*\)".*/\1/' | head -1)
        arch=$(grep 'io.daemonless.arch\s*=' "$cf" | sed 's/.*arch\s*=\s*"\([^"]*\)".*/\1/' | head -1)
        mlock=$(grep 'org.freebsd.jail.allow.mlock\s*=' "$cf" | head -1)
        url=$(grep 'org.opencontainers.image.url\s*=' "$cf" | sed 's/.*url\s*=\s*"\([^"]*\)".*/\1/' | head -1)

        # Determine if .NET (needs mlock)
        dotnet="false"
        [ -n "$mlock" ] && dotnet="true"

        # Determine if ARM64 supported
        arm64="false"
        echo "$arch" | grep -q "arm64\|aarch64" && arm64="true"

        # Get primary port (first one if multiple)
        primary_port=$(echo "$port" | cut -d',' -f1)
        extra_ports=$(echo "$port" | cut -d',' -f2- | tr ',' ' ')
        [ "$extra_ports" = "$primary_port" ] && extra_ports=""

        # Get volumes from label
        volumes=$(grep 'io.daemonless.volumes\s*=' "$cf" | sed 's/.*volumes\s*=\s*"\([^"]*\)".*/\1/' | head -1)

        # Get config mount from label (default: /config)
        config_mount=$(grep 'io.daemonless.config-mount\s*=' "$cf" | sed 's/.*config-mount\s*=\s*"\([^"]*\)".*/\1/' | head -1)
        [ -z "$config_mount" ] && config_mount="/config"

        # Get network from label (default: empty = bridge)
        network=$(grep 'io.daemonless.network\s*=' "$cf" | sed 's/.*network\s*=\s*"\([^"]*\)".*/\1/' | head -1)

        # Clean description (remove " on FreeBSD" suffix for display)
        short_desc=$(echo "$desc" | sed 's/ on FreeBSD//')

        # Output JSON-ish line
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "$name" "$short_desc" "$primary_port" "$dotnet" "$arm64" "$volumes" "$extra_ports" "$config_mount" "$network" "$url"
    done
}

# Generate the HTML
generate_html() {
    cat << 'HEADER'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>daemonless Command Generator</title>
    <link href="https://cdn.jsdelivr.net/npm/tom-select@2.3.1/dist/css/tom-select.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/tom-select@2.3.1/dist/js/tom-select.complete.min.js"></script>
    <style>
        :root {
            --bg: #ffffff;
            --bg-light: #f5f5f5;
            --accent: #e0e0e0;
            --text: #333333;
            --text-muted: #666666;
            --highlight: #0066cc;
            --success: #228b22;
            --border: #cccccc;
        }
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg);
            color: var(--text);
            margin: 0;
            padding: 20px;
            line-height: 1.6;
        }
        .container { max-width: 900px; margin: 0 auto; }
        h1 { color: var(--highlight); margin-bottom: 10px; }
        .subtitle { color: var(--text-muted); margin-bottom: 30px; }
        .subtitle a { color: var(--success); text-decoration: none; }
        .card {
            background: var(--bg-light);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
        }
        .card h2 {
            margin-top: 0;
            color: var(--success);
            font-size: 1.1em;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .form-group { margin-bottom: 15px; }
        label { display: block; margin-bottom: 5px; color: var(--text-muted); font-size: 0.9em; }
        input, select {
            width: 100%;
            padding: 10px 12px;
            background: var(--bg);
            border: 1px solid var(--border);
            border-radius: 4px;
            color: var(--text);
            font-size: 14px;
        }
        input:focus, select:focus { outline: none; border-color: var(--highlight); }
        .row { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; }
        .row-3 { grid-template-columns: 1fr 1fr 1fr; }
        .output-section { position: relative; }
        .output-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; }
        .output-header h2 { margin: 0; }
        .tabs { display: flex; gap: 10px; }
        .tab {
            padding: 6px 12px;
            background: var(--bg);
            border: 1px solid var(--border);
            border-radius: 4px;
            color: var(--text-muted);
            cursor: pointer;
            font-size: 0.85em;
        }
        .tab.active { background: var(--accent); border-color: var(--highlight); color: var(--text); }
        pre {
            background: #f8f8f8;
            border: 1px solid var(--border);
            border-radius: 4px;
            padding: 15px;
            overflow-x: auto;
            margin: 0;
            font-family: 'SF Mono', 'Fira Code', monospace;
            font-size: 13px;
            line-height: 1.5;
        }
        .copy-btn {
            position: absolute;
            top: 45px;
            right: 10px;
            padding: 8px 12px;
            background: var(--accent);
            border: 1px solid var(--border);
            border-radius: 4px;
            color: var(--text);
            cursor: pointer;
            font-size: 0.85em;
        }
        .copy-btn:hover { background: var(--highlight); }
        .copy-btn.copied { background: var(--success); color: var(--bg); }
        .info {
            background: var(--accent);
            border-left: 3px solid var(--highlight);
            padding: 10px 15px;
            margin-top: 15px;
            font-size: 0.9em;
            border-radius: 0 4px 4px 0;
        }
        .info a { color: var(--highlight); }
        .volume-group { display: flex; gap: 10px; align-items: end; }
        .volume-group .form-group { flex: 1; margin-bottom: 0; }
        .add-btn, .remove-btn {
            padding: 10px 15px;
            border: 1px solid var(--border);
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
        }
        .add-btn { background: var(--accent); color: var(--text); margin-top: 10px; }
        .remove-btn { background: var(--highlight); color: var(--text); }
        .badge {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 3px;
            font-size: 0.75em;
            margin-left: 8px;
        }
        .badge-dotnet { background: #512bd4; }
        .badge-arm64 { background: var(--success); color: var(--bg); }
        footer { text-align: center; margin-top: 40px; color: var(--text-muted); font-size: 0.85em; }
        footer a { color: var(--success); text-decoration: none; }
        /* Tom Select styling */
        .ts-wrapper { width: 100%; }
        .ts-control { padding: 8px 12px !important; }
        .ts-wrapper.focus .ts-control { border-color: var(--highlight) !important; box-shadow: none !important; }
    </style>
</head>
<body>
    <div class="container">
        <h1>daemonless Command Generator</h1>
        <p class="subtitle">FreeBSD Podman container commands &mdash; <a href="https://github.com/buhnux/daemonless">GitHub</a></p>

        <div class="card">
            <h2>Select Image</h2>
            <div class="form-group">
                <label for="image">Container Image</label>
                <select id="image">
HEADER

    # Generate options from extracted data
    extract_images | sort | while IFS='|' read -r name desc port dotnet arm64 volumes extra_ports config_mount network url; do
        [ -z "$name" ] && continue
        printf '                    <option value="%s">%s - %s</option>\n' "$name" "$name" "$desc"
    done

    cat << 'MIDDLE'
                </select>
            </div>
            <div id="image-info"></div>
        </div>

        <div class="card">
            <h2>Configuration</h2>
            <div class="row">
                <div class="form-group">
                    <label for="name">Container Name</label>
                    <input type="text" id="name" value="" oninput="generate()">
                </div>
                <div class="form-group">
                    <label for="tag">Image Tag</label>
                    <select id="tag" onchange="generate()">
                        <option value="latest">:latest (upstream)</option>
                        <option value="pkg">:pkg (FreeBSD quarterly)</option>
                        <option value="pkg-latest">:pkg-latest (FreeBSD latest)</option>
                    </select>
                </div>
            </div>
            <div class="row row-3">
                <div class="form-group">
                    <label for="puid">PUID</label>
                    <input type="text" id="puid" value="1000" oninput="generate()">
                </div>
                <div class="form-group">
                    <label for="pgid">PGID</label>
                    <input type="text" id="pgid" value="1000" oninput="generate()">
                </div>
                <div class="form-group">
                    <label for="tz">Timezone</label>
                    <select id="tz"></select>
                </div>
            </div>
        </div>

        <div class="card">
            <h2>Volumes</h2>
            <div class="form-group">
                <label for="config-path">Config Path (host)</label>
                <input type="text" id="config-path" value="/data/config/" oninput="generate()">
            </div>
            <div id="default-volumes"></div>
            <div id="extra-volumes"></div>
            <button class="add-btn" onclick="addVolume()">+ Add Volume</button>
        </div>

        <div class="card output-section">
            <div class="output-header">
                <h2>Output</h2>
                <div class="tabs">
                    <button class="tab active" onclick="showTab('run')">podman run</button>
                    <button class="tab" onclick="showTab('compose')">compose.yaml</button>
                </div>
            </div>
            <button class="copy-btn" onclick="copyOutput()">Copy</button>
            <pre><code id="output"></code></pre>
        </div>

        <div class="info">
            Build images first: <code>./scripts/local-build.sh 15 &lt;image&gt; latest</code><br>
            .NET apps need <a href="https://github.com/buhnux/daemonless#ocijail-patch">patched ocijail</a>
        </div>

        <footer>
            <p>daemonless - FreeBSD Podman Containers &mdash; <a href="https://github.com/buhnux/daemonless">GitHub</a></p>
            <p style="font-size: 0.8em;">Generated: GENERATED_DATE</p>
        </footer>
    </div>

    <script>
        let currentTab = 'run';
        let extraVolumes = [];

        const images = {
MIDDLE

    # Generate JavaScript object from extracted data
    extract_images | sort | while IFS='|' read -r name desc port dotnet arm64 volumes extra_ports config_mount network url; do
        [ -z "$name" ] && continue

        # Build volumes array
        vol_array="[]"
        if [ -n "$volumes" ]; then
            vol_array="["
            first=true
            echo "$volumes" | tr ',' '\n' | while read -r v; do
                [ -z "$v" ] && continue
                $first || vol_array="${vol_array},"
                vol_array="${vol_array}'$v'"
                first=false
            done
            vol_array="${vol_array}]"
            # Rebuild properly
            vol_array=$(echo "$volumes" | sed "s/,/', '/g" | sed "s/^/['/" | sed "s/$/']/" )
        fi

        # Build extra ports array
        ep_array=""
        if [ -n "$extra_ports" ]; then
            ep_array=$(echo "$extra_ports" | tr ' ' ',' | sed "s/,/', '/g" | sed "s/^/, extraPorts: ['/" | sed "s/$/']/" )
        fi

        # Config mount if not /config
        cm_str=""
        [ "$config_mount" != "/config" ] && cm_str=", configMount: '$config_mount'"

        # Network if specified
        net_str=""
        [ -n "$network" ] && net_str=", network: '$network'"

        printf "            '%s': { port: %s, dotnet: %s, arm64: %s, volumes: %s%s%s%s },\n" \
            "$name" "${port:-null}" "$dotnet" "$arm64" "$vol_array" "$ep_array" "$cm_str" "$net_str"
    done

    cat << 'FOOTER'
        };

        function updateForm() {
            const select = document.getElementById('image');
            const image = select.value;
            const config = images[image];
            if (!config) return;

            document.getElementById('name').value = image;
            document.getElementById('config-path').value = `/data/config/${image}`;

            let info = '';
            if (config.dotnet) info += '<span class="badge badge-dotnet">.NET</span>';
            if (config.arm64) info += '<span class="badge badge-arm64">ARM64</span>';
            document.getElementById('image-info').innerHTML = info;

            const defaultVolumesDiv = document.getElementById('default-volumes');
            defaultVolumesDiv.innerHTML = '';
            (config.volumes || []).forEach(vol => {
                const div = document.createElement('div');
                div.className = 'form-group';
                div.innerHTML = `<label>${vol} (host path)</label>
                    <input type="text" class="default-volume" data-mount="${vol}" value="/data${vol}" oninput="generate()">`;
                defaultVolumesDiv.appendChild(div);
            });

            extraVolumes = [];
            document.getElementById('extra-volumes').innerHTML = '';
            generate();
        }

        function addVolume() {
            const id = extraVolumes.length;
            extraVolumes.push({ host: '', container: '' });
            const div = document.createElement('div');
            div.className = 'volume-group';
            div.id = `extra-vol-${id}`;
            div.innerHTML = `
                <div class="form-group"><label>Host Path</label>
                    <input type="text" placeholder="/path/on/host" oninput="updateExtraVolume(${id}, 'host', this.value)"></div>
                <div class="form-group"><label>Container Path</label>
                    <input type="text" placeholder="/path/in/container" oninput="updateExtraVolume(${id}, 'container', this.value)"></div>
                <div class="form-group"><button class="remove-btn" onclick="removeVolume(${id})">-</button></div>`;
            document.getElementById('extra-volumes').appendChild(div);
        }

        function updateExtraVolume(id, field, value) { extraVolumes[id][field] = value; generate(); }
        function removeVolume(id) { document.getElementById(`extra-vol-${id}`).remove(); extraVolumes[id] = null; generate(); }

        function showTab(tab) {
            currentTab = tab;
            document.querySelectorAll('.tab').forEach((t, i) => t.classList.toggle('active', (tab === 'run') === (i === 0)));
            generate();
        }

        function generate() {
            const image = document.getElementById('image').value;
            const name = document.getElementById('name').value || image;
            const tag = document.getElementById('tag').value;
            const puid = document.getElementById('puid').value;
            const pgid = document.getElementById('pgid').value;
            const tz = document.getElementById('tz').value;
            const configPath = document.getElementById('config-path').value;
            const config = images[image];
            if (!config) return;

            const volumes = [];
            const configMount = config.configMount || '/config';
            volumes.push({ host: configPath, container: configMount });
            document.querySelectorAll('.default-volume').forEach(input => {
                volumes.push({ host: input.value, container: input.dataset.mount });
            });
            extraVolumes.forEach(vol => { if (vol && vol.host && vol.container) volumes.push(vol); });

            const ports = [];
            if (config.port) ports.push(`${config.port}:${config.port}`);
            (config.extraPorts || []).forEach(p => {
                if (p.includes('/')) {
                    const [num, proto] = p.split('/');
                    ports.push(`${num}:${num}/${proto}`);
                } else {
                    ports.push(`${p}:${p}`);
                }
            });

            if (currentTab === 'run') {
                let cmd = `podman run -d --name ${name}`;
                if (config.network === 'host') {
                    cmd += ` \\\n  --network=host`;
                } else {
                    ports.forEach(p => cmd += ` \\\n  -p ${p}`);
                }
                if (config.dotnet) cmd += ` \\\n  --annotation 'org.freebsd.jail.allow.mlock=true'`;
                cmd += ` \\\n  -e PUID=${puid} -e PGID=${pgid}`;
                cmd += ` \\\n  -e TZ=${tz}`;
                volumes.forEach(v => cmd += ` \\\n  -v ${v.host}:${v.container}`);
                cmd += ` \\\n  ghcr.io/daemonless/${image}:${tag}`;
                document.getElementById('output').textContent = cmd;
            } else {
                let yaml = `services:\n  ${name}:\n`;
                yaml += `    image: ghcr.io/daemonless/${image}:${tag}\n`;
                yaml += `    container_name: ${name}\n`;
                yaml += `    environment:\n      - PUID=${puid}\n      - PGID=${pgid}\n      - TZ=${tz}\n`;
                yaml += `    volumes:\n`;
                volumes.forEach(v => yaml += `      - ${v.host}:${v.container}\n`);
                if (config.network !== 'host' && ports.length) {
                    yaml += `    ports:\n`;
                    ports.forEach(p => yaml += `      - ${p}\n`);
                }
                if (config.network === 'host') yaml += `    network_mode: host\n`;
                if (config.dotnet) yaml += `    annotations:\n      org.freebsd.jail.allow.mlock: "true"\n`;
                yaml += `    restart: unless-stopped`;
                document.getElementById('output').textContent = yaml;
            }
        }

        function copyOutput() {
            navigator.clipboard.writeText(document.getElementById('output').textContent).then(() => {
                const btn = document.querySelector('.copy-btn');
                btn.textContent = 'Copied!';
                btn.classList.add('copied');
                setTimeout(() => { btn.textContent = 'Copy'; btn.classList.remove('copied'); }, 2000);
            });
        }

        // Initialize image selector with Tom Select
        const imageSelect = new TomSelect('#image', {
            create: false,
            sortField: { field: 'text' },
            onChange: updateForm
        });

        // Initialize timezone selector with Tom Select
        let tzSelect;
        (function() {
            let timezones;
            try {
                timezones = Intl.supportedValuesOf('timeZone');
            } catch (e) {
                // Fallback for older browsers
                timezones = ['America/New_York', 'America/Chicago', 'America/Denver',
                    'America/Los_Angeles', 'Europe/London', 'Europe/Paris', 'Europe/Berlin',
                    'Asia/Tokyo', 'Asia/Shanghai', 'Australia/Sydney', 'Pacific/Auckland', 'UTC'];
            }

            tzSelect = new TomSelect('#tz', {
                options: timezones.map(tz => ({ value: tz, text: tz })),
                items: ['America/New_York'],
                maxOptions: null,
                create: false,
                sortField: { field: 'text' },
                onChange: generate
            });
        })();

        updateForm();
    </script>
</body>
</html>
FOOTER
}

# Generate and add timestamp
generate_html | sed "s/GENERATED_DATE/$(date '+%Y-%m-%d %H:%M')/" > "$OUTPUT"

echo "Generated: $OUTPUT"
echo "Images found: $(extract_images | wc -l | tr -d ' ')"
