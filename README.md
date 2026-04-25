# OSINTel Dashboard — v3.0

> A glassmorphic, dual-theme recon suite. Flask backend. 70+ tools. Built for operators.

![Python](https://img.shields.io/badge/Python-3.8+-3ae0ff?style=flat-square&logo=python&logoColor=white)
![Flask](https://img.shields.io/badge/Flask-2.x-00ffb2?style=flat-square&logo=flask&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-a050ff?style=flat-square)
![Status](https://img.shields.io/badge/Status-Actively%20Developed-00ffb2?style=flat-square)

---

## ⚠️ Disclaimer

**FOR EDUCATIONAL AND AUTHORIZED RESEARCH PURPOSES ONLY.**

You are solely responsible for your actions. Always obtain explicit written permission before scanning or testing any target you do not own. The creators and contributors assume **no liability** for misuse or damage caused by this software. Use responsibly and legally.

---

## What's New in v3.0

- **Full UI rewrite** — glassmorphic dual-theme interface (dark/light) with JetBrains Mono + Syne typography, scanline overlays, ambient depth orbs, and macOS-style terminal output
- **`ctfr.py` upgraded** — now a proper module with `--no-banner`, `--json`, `--timeout`, wildcard filtering, multi-name cert parsing, and full dashboard integration
- **70+ tools pre-wired** in `data.json` across recon, web enum, exploitation, forensics, crypto, OSINT, wireless, and binary analysis
- **Streaming execution** via Server-Sent Events on `/api/run_tool_stream/<id>`
- **Hardened backend** — `shlex`-based command splitting (no `shell=True`), path traversal guards, atomic JSON saves, per-tool timeout override, and `MAX_HISTORY_ENTRIES` cap
- **Live tool search** in sidebar, welcome dashboard with run stats, breadcrumb navigation, copy-to-clipboard on output
- **History improvements** — status badges (success/error), per-entry timestamps, output file previews

---

## Features

- **Glassmorphic UI** — layered `rgba` backgrounds, `backdrop-filter: blur()`, dual CSS variable theme system switchable at runtime
- **Flask backend** — `shell=False` subprocess execution, SSE streaming, atomic JSON I/O, configurable timeouts
- **Tool management** — add, edit, delete tools with full form UI; supports git clone + pip install on add
- **Execution history** — per-tool and global history, saved output files, click-to-reload past results
- **Template substitution** — `{{field_id}}` placeholders in command templates, shell-quoted per value
- **Custom handlers** — extensible `CUSTOM_HANDLERS` dict in `app.py` for tools needing special logic (e.g. `ffuf-file-finder`)
- **Output persistence** — all runs saved to `data/` with configurable filename patterns
- **Clickable URLs** — auto-linked in terminal output

---

## Tool Categories

### Passive Recon & Subdomain Enumeration
`ctfr` · `subfinder` · `assetfinder` · `amass` · `sublist3r` · `fierce` · `dnstwist` · `dnsdumpster` · `crt.sh` · `waybackurls` · `theHarvester` · `recon-ng` · `spiderfoot`

### DNS & Network
`nslookup` · `dnsrecon` · `dnsenum` · `dnsx` · `whois/rdap` · `ping` · `fping` · `hping3` · `arp` · `netstat` · `ss` · `ip addr` · `tcpdump` · `snmpwalk` · `traceroute` · `mtr` · `nc` · `socat`

### Web Enumeration & Content Discovery
`gobuster` · `ffuf` · `feroxbuster` · `dirb` · `wfuzz` · `gau` · `gauplus` · `httpx` · `httprobe` · `robots.txt fetcher` · `curl headers` · `wafw00f` · `arjun` · `whatweb` · `WPScan` · `JoomScan` · `CMSeeK`

### Vulnerability Scanning & Exploitation
`nmap` (port scan + vuln scripts) · `masscan` · `nuclei` · `nikto` · `sqlmap` · `dalfox` · `XSStrike` · `commix` · `Medusa` · `Ncrack` · `hydra` · `Responder` · `CrackMapExec` · `Impacket secretsdump`

### TLS / SSL Analysis
`openssl cert inspector` · `sslyze` · `testssl.sh` · `sslscan`

### OSINT & Enrichment
`shodan` · `censys` · `VirusTotal` · `urlscan` · `ipinfo` · `abuseipdb` · `emailrep` · `socialscan` · `maigret` · `holehe` · `GHunt` · `photon` · `cloud-enum` · `AWS S3 check`

### Secrets & Git
`gitleaks` · `trufflehog` · `git-dumper`

### Password & Hash
`hashcat` · `john` · `hashid` · `openssl dgst` · `aircrack-ng` · `crunch` · `CeWL`

### Steganography & Forensics
`steghide` · `stegseek` · `binwalk` · `foremost` · `volatility3` · `exiftool` · `pdfinfo` · `strings`

### Binary Analysis & Reverse Engineering
`objdump` · `readelf` · `ltrace` · `strace` · `checksec` · `ghidra headless` · `file`

### Utilities
`base64` · `xxd` · `tr/ROT13` · `awk` · `sed` · `sort/uniq` · `grep` · `find` · `lsof` · `ps` · `URL parser` · `Python decode helper` · `public IP lookup` · `airodump-ng`

---

## Tech Stack

| Layer | Tech |
|---|---|
| Backend | Python 3.8+, Flask |
| Frontend | HTML5, CSS3 (custom properties), Vanilla JS |
| Fonts | JetBrains Mono, Syne (Google Fonts) |
| Icons | Font Awesome 6 |
| Storage | `data.json` (tool configs), `history.json` (run logs), `data/` (output files) |
| Execution | `subprocess.Popen` — `shell=False`, SSE streaming |

---

## Prerequisites

Designed and tested on **Debian-based Linux** (Ubuntu, Kali, Debian). Core requirements:

| Requirement | Check | Install |
|---|---|---|
| Python 3.8+ | `python3 --version` | `sudo apt install python3` |
| pip | `pip3 --version` | `sudo apt install python3-pip` |
| venv | — | `sudo apt install python3-venv` |
| git | `git --version` | `sudo apt install git` |
| curl | `curl --version` | `sudo apt install curl` |

---

## Installation

### Method 1 — Setup Script (Recommended)

```bash
git clone https://github.com/aenoshrajora/OSINTel-Dashboard.git
cd OSINTel-Dashboard
chmod +x setup.sh
./setup.sh
```

The script handles: venv creation, pip packages, apt tool installs, and cloning optional tools. Follow the on-screen prompts. `sudo` is only requested for `apt` steps.

**Post-setup checklist:**
- **GHunt:** run `python3 check_and_gen_cookies.py` inside `tools/GHunt/GHunt/` to generate `cookies.json`
- **`data.json` paths:** verify `clone_dir` and `run_in_directory` match your actual clone locations
- **`data/` directory:** created by setup script; if missing run `mkdir data`

### Method 2 — Manual

```bash
# 1. Clone project
git clone https://github.com/aenoshrajora/OSINTel-Dashboard.git
cd OSINTel-Dashboard

# 2. System dependencies
sudo apt update
sudo apt install -y python3 python3-pip python3-venv git curl \
  whois nmap dnsrecon whatweb libimage-exiftool-perl ffuf

# 3. Virtual environment
python3 -m venv venv
source venv/bin/activate

# 4. Python packages
pip install Flask requests

# 5. Directories
mkdir -p data tools

# 6. Clone optional tools (examples)
cd tools
git clone https://github.com/sherlock-project/sherlock.git sherlock
git clone https://github.com/aboul3la/Sublist3r.git Sublist3r
git clone https://github.com/mxrch/GHunt.git GHunt
git clone https://github.com/laramies/metagoofil.git metagoofil
cd ..

# Install requirements for cloned tools
pip install -r tools/sherlock/sherlock/requirements.txt
pip install -r tools/Sublist3r/requirements.txt
```

---

## ctfr.py — Certificate Transparency Recon (v1.3)

`ctfr.py` is a first-class module in v3.0, not just a bundled script.

```bash
# Basic usage
python3 ctfr.py -d example.com

# Dashboard-friendly (no banner, clean output)
python3 ctfr.py -d example.com --no-banner

# JSON output
python3 ctfr.py -d example.com --no-banner --json

# Save to file
python3 ctfr.py -d example.com --no-banner -o /tmp/subs.txt

# Custom timeout
python3 ctfr.py -d example.com --timeout 30
```

**Changes from v1.2:**
- `--no-banner` flag for clean programmatic invocation from the dashboard
- `--json` output with `{domain, subdomains, count}` structure
- `--timeout` flag passed through to requests
- Wildcard entries (`*.example.com`) stripped automatically
- Multi-name `name_value` fields parsed (newline-separated certs)
- Protocol, query string, and fragment stripped from input URL
- File output uses `"w"` (overwrite) not `"a"` (append)
- Proper `RuntimeError` handling for timeouts, connection errors, bad JSON

Update the `crt-sh-builtin` entry in `data.json` to use it:
```
python3 ctfr.py -d {{domain}} --no-banner
```

---

## Running the Application

```bash
# Activate venv
source venv/bin/activate

# Start server
python3 app.py
```

Access at `http://localhost:5001` (or `http://YOUR_LAN_IP:5001` from another machine on the network).

Environment overrides:

```bash
PORT=8080 HOST=127.0.0.1 FLASK_DEBUG=1 python3 app.py
```

---

## API Reference

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/tools` | List all tool configs |
| `POST` | `/api/tools` | Add a new tool (clones repo if needed) |
| `PUT` | `/api/tools/<id>` | Update tool config |
| `DELETE` | `/api/tools/<id>` | Delete tool + cloned directory |
| `POST` | `/api/run_tool/<id>` | Execute tool, return full output |
| `POST` | `/api/run_tool_stream/<id>` | Execute tool, stream output via SSE |
| `GET` | `/api/history/<tool_id>` | Tool-specific history |
| `GET` | `/api/history?limit=N` | Global history (latest N entries) |
| `DELETE` | `/api/history` | Clear all history (`?purge_files=true` to delete output files too) |
| `GET` | `/api/history_file_content?filepath=` | Read saved output file |
| `GET` | `/data/<filename>` | Download output file |

### Command Template Syntax

```
nmap -sV {{flags}} {{target}}
python3 ctfr.py -d {{domain}} --no-banner -o {{output}}
```

Tokens in command templates are replaced with shell-quoted user input values. Filename pattern tokens:

| Token | Resolves to |
|---|---|
| `{{TOOL_ID}}` | Tool's UUID |
| `{{TOOL_NAME_SANITIZED}}` | Lowercased, special-chars-stripped name |
| `{{INPUT__field_id}}` | Value of that input field |
| `{{TIMESTAMP}}` | `YYYYMMDD_HHMMSS` |
| `{{UUID}}` | Random 8-char hex |

---

## Adding Custom Tools

1. Click **+ new tool** in the sidebar
2. Fill in name, description, and command template using `{{field_id}}` placeholders
3. Add input field definitions (text, select, URL, password, email types supported)
4. Optionally enable git clone — the backend will clone the repo and pip-install requirements on save
5. Set an output filename pattern

For tools needing special execution logic, add a handler to `CUSTOM_HANDLERS` in `app.py`:

```python
def _handle_my_tool(tool_config, user_inputs):
    # ... custom logic ...
    return output_string, success_bool

CUSTOM_HANDLERS['my-tool-id'] = _handle_my_tool
```

---

## Project Structure

```
OSINTel-Dashboard/
├── app.py              # Flask backend — routing, execution, history
├── ctfr.py             # Certificate transparency recon module (v1.3)
├── data.json           # Tool configurations (70+ pre-wired)
├── history.json        # Execution log (auto-managed)
├── setup.sh            # Interactive install script
├── data/               # Saved tool output files (auto-created)
├── tools/              # Cloned tool repositories (auto-created)
│   ├── sherlock/
│   ├── Sublist3r/
│   ├── GHunt/
│   └── ...
└── templates/
    └── index.html      # Frontend — glassmorphic dual-theme UI
```

---

## Troubleshooting

**"Command not found"** — tool not installed globally. Check `sudo apt install <tool>` or the tool's own install docs.

**Python errors on startup** — activate your venv first: `source venv/bin/activate`. Check Flask is installed.

**Tool clone fails on save** — verify the git URL is reachable and you have internet access. Check `install_log` in the modal response.

**ctfr returns no results** — crt.sh can be slow or temporarily down. Try increasing `--timeout`. Check connectivity with `curl -s 'https://crt.sh/?q=%.example.com&output=json'`.

**GHunt not working** — missing or expired `cookies.json`. Navigate to `tools/GHunt/GHunt/` and re-run `python3 check_and_gen_cookies.py`.

**Output file not found in history** — ensure `data/` directory exists and Flask process has write permission.

**Streaming endpoint not updating** — verify the client supports SSE (`EventSource` or `fetch` + `ReadableStream`). Custom-handled tools fall back to the standard (non-streaming) endpoint automatically.

---

## Contributing

Issues and pull requests are welcome. If you want to add a tool to `data.json`, follow the existing schema — include `id`, `name`, `description`, `command_template`, `input_fields`, and `output_filename_pattern` at minimum.

For backend changes, keep the `shell=False` constraint and run new command strings through `build_command_list()` before passing to `run_command()`.

---

## License

MIT — see `LICENSE` for details.

---

*OSINTel Dashboard is built for security researchers, CTF players, and red teamers. Use it on infrastructure you own or have explicit authorization to test.*