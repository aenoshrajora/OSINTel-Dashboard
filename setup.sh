#!/usr/bin/env bash
# setup.sh — OSINTel Dashboard v3.0 setup
# Installs system deps, Go tools, Python venv packages, and clonable tools.
# Run: chmod +x setup.sh && ./setup.sh
# WARNING: This script runs system-wide package installs (sudo apt). Review before running.

set -o errexit
set -o pipefail
set -o nounset

###############################
# Configuration / variables
###############################
VENV_DIR="./venv"
TOOLS_DIR="./tools"
DATA_DIR="./data"

# Go-based tools (installed via go install into $GOBIN)
GOMODTOOLS=(
  "github.com/owasp-amass/amass/v3/...@latest"
  "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
  "github.com/tomnomnom/assetfinder@latest"
  "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
  "github.com/tomnomnom/waybackurls@latest"
  "github.com/lc/gau/v2/cmd/gau@latest"
  "github.com/bp0lr/gauplus@latest"
  "github.com/hakluke/hakrawler@latest"
  "github.com/tomnomnom/httprobe@latest"
  "github.com/projectdiscovery/httpx/cmd/httpx@latest"
  "github.com/projectdiscovery/nuclei/v2/cmd/nuclei@latest"
  "github.com/haccer/subjack@latest"
  "github.com/hahwul/dalfox/v2@latest"
  "github.com/trufflesecurity/trufflehog/v3@latest"
)

# System apt packages
APT_PACKAGES=(
  # Core utilities
  python3 python3-pip python3-venv git curl wget build-essential make gcc golang
  # DNS / network recon
  nmap whois dnsutils dnsrecon dnsenum host traceroute mtr
  # Network tools
  netcat-openbsd socat fping hping3
  netstat-nat   # provides netstat (or use 'net-tools' below)
  net-tools     # arp, netstat, ifconfig
  # Packet capture
  tcpdump wireshark-common
  # SNMP
  snmp snmpd
  # Web enumeration
  gobuster dirb ffuf nikto whatweb
  # Vuln / exploitation
  sqlmap hydra medusa ncrack commix
  # Wireless
  aircrack-ng
  # Password / hash
  hashcat john crunch cewl
  # Steganography / forensics
  steghide stegseek binwalk foremost
  # Binary analysis
  binutils ltrace strace exiftool
  # SSL / TLS
  openssl sslscan
  # File utilities
  jq ripgrep poppler-utils
  # Other
  masscan zmap smbclient
)

# Python packages installed into the venv (app runtime + tool wrappers)
PYPI_PACKAGES_VENV=(
  # App core
  Flask
  requests
  # OSINT / recon
  theHarvester
  sublist3r
  fierce
  dnstwist
  socialscan
  # Web analysis
  wafw00f
  arjun
  wfuzz
  sslyze
  # Hash tools
  hashid
  # Secrets scanning
  gitleaks
  # Cloud / API clients
  shodan
  vt-py
  # Impacket (AD / Windows post-exploitation)
  impacket
)

# Python packages installed system-wide (tools that need to run with sudo or outside venv)
PYPI_PACKAGES_SYSTEM=(
  holehe
)

# Clonable tools — format: "Display Name|target dir|git URL|post-install command"
# These match the clone_url / clone_dir entries in data.json exactly.
CLONABLE_TOOLS=(
  "Sherlock (username search)|${TOOLS_DIR}/sherlock|https://github.com/sherlock-project/sherlock.git|pip install -r requirements.txt 2>/dev/null || true"
  "Sublist3r (subdomain enum)|${TOOLS_DIR}/Sublist3r|https://github.com/aboul3la/Sublist3r.git|pip install -r requirements.txt 2>/dev/null || true"
  "GHunt (Google OSINT)|${TOOLS_DIR}/GHunt|https://github.com/mxrch/GHunt.git|pip install -r GHunt/requirements.txt 2>/dev/null || true"
  "Metagoofil (metadata extractor)|${TOOLS_DIR}/metagoofil|https://github.com/laramies/metagoofil.git|echo 'No pip requirements for metagoofil.'"
  "XSStrike (XSS suite)|${TOOLS_DIR}/XSStrike|https://github.com/s0md3v/XSStrike.git|pip install -r requirements.txt 2>/dev/null || true"
  "git-dumper (.git dumper)|${TOOLS_DIR}/git-dumper|https://github.com/arthaud/git-dumper.git|pip install -r requirements.txt 2>/dev/null || true"
  "cloud_enum (AWS/GCP/Azure)|${TOOLS_DIR}/cloud_enum|https://github.com/initstring/cloud_enum.git|pip install -r requirements.txt 2>/dev/null || true"
  "Photon (web crawler)|${TOOLS_DIR}/Photon|https://github.com/s0md3v/Photon.git|pip install -r requirements.txt 2>/dev/null || true"
  "CMSeeK (CMS scanner)|${TOOLS_DIR}/CMSeeK|https://github.com/Tuhinshubhra/CMSeeK.git|pip install -r requirements.txt 2>/dev/null || true"
  "maigret (username OSINT)|${TOOLS_DIR}/maigret|https://github.com/soxoj/maigret.git|pip install -r requirements.txt 2>/dev/null || true"
  "API-dnsdumpster|${TOOLS_DIR}/dnsdumpster|https://github.com/PaulSec/API-dnsdumpster.com.git|pip install -r requirements.txt 2>/dev/null || true"
)

###############################
# Helpers
###############################
command_exists() { command -v "$1" >/dev/null 2>&1; }

warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
info() { echo -e "\e[36m[INFO]\e[0m $*"; }
ok()   { echo -e "\e[32m[ OK ]\e[0m $*"; }
die()  { echo -e "\e[31m[ERR ]\e[0m $*"; exit 1; }

###############################
# Banner
###############################
echo ""
echo -e "\e[36m  ___  ____ ___ _   _ _____      _\e[0m"
echo -e "\e[36m / _ \\/ ___|_ _| \\ | |_   _|__ _| |\e[0m"
echo -e "\e[36m| | | \\___ \\| ||  \\| | | |/ _\` | |\e[0m"
echo -e "\e[36m| |_| |___) | || |\\  | | | (_| | |\e[0m"
echo -e "\e[36m \\___/|____/___|_| \\_| |_|\\__,_|_|\e[0m"
echo ""
echo "  OSINTel Dashboard — Setup Script v3.0"
echo "  https://github.com/aenoshrajora/OSINTel-Dashboard"
echo ""
echo "  ⚠  FOR AUTHORIZED TESTING ONLY. Use responsibly."
echo "  ⚠  This script runs sudo apt and sudo pip3. Review before proceeding."
echo "------------------------------------------------------"
echo ""

# Confirm
read -r -p "Proceed with installation? (y/N): " proceed
if [[ ! "${proceed:-}" =~ ^[Yy]$ ]]; then
  die "User aborted."
fi

###############################
# 1. System package installs
###############################
info "Updating apt package lists..."
sudo apt update -y
sudo apt upgrade -y

info "Installing APT packages (this may take a while)..."
# Build the list carefully — some package names differ across distros; failures are warned, not fatal
failed_apt=()
for pkg in "${APT_PACKAGES[@]}"; do
  if ! sudo apt install -y "$pkg" 2>/dev/null; then
    warn "apt install failed for: $pkg (may not be available on this distro)"
    failed_apt+=("$pkg")
  fi
done

if [ ${#failed_apt[@]} -gt 0 ]; then
  warn "The following apt packages failed: ${failed_apt[*]}"
  warn "You can install them manually after the script completes."
fi

# Optional apt packages — check availability first
for opt_pkg in recon-ng enum4linux wpscan joomscan spiderfoot; do
  if apt-cache show "$opt_pkg" >/dev/null 2>&1; then
    info "Installing optional package: $opt_pkg"
    sudo apt install -y "$opt_pkg" || warn "$opt_pkg apt install failed."
  else
    warn "$opt_pkg not in apt repo on this system — install manually if needed."
  fi
done

###############################
# 2. Create project directories
###############################
info "Creating project directories..."
mkdir -p "$TOOLS_DIR" "$DATA_DIR"
ok "Directories ready: $TOOLS_DIR  $DATA_DIR"

###############################
# 3. Python virtual environment
###############################
if [ ! -d "$VENV_DIR" ]; then
  info "Creating Python virtual environment at $VENV_DIR..."
  python3 -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
info "Virtual environment active."

info "Upgrading pip, setuptools, wheel..."
pip install --upgrade pip setuptools wheel

# Install venv packages
info "Installing Python packages into venv..."
failed_pip=()
for pkg in "${PYPI_PACKAGES_VENV[@]}"; do
  if ! pip install "$pkg"; then
    warn "pip install failed for: $pkg"
    failed_pip+=("$pkg")
  fi
done

if [ ${#failed_pip[@]} -gt 0 ]; then
  warn "The following pip packages failed: ${failed_pip[*]}"
fi

# System-wide pip packages (holehe needs to run outside venv with sudo in some setups)
info "Installing system-wide pip packages: ${PYPI_PACKAGES_SYSTEM[*]}"
if command_exists pip3; then
  sudo pip3 install --break-system-packages "${PYPI_PACKAGES_SYSTEM[@]}" \
    || warn "sudo pip3 install failed for some system-wide packages."
else
  warn "pip3 not found for system-wide install."
fi

###############################
# 4. Go toolchain + Go tools
###############################
if ! command_exists go; then
  info "Go not found — attempting apt install..."
  sudo apt install -y golang || die "golang install failed. Install Go manually and re-run."
fi

GOBIN_DEFAULT="$HOME/go/bin"
export GOBIN="${GOBIN:-$GOBIN_DEFAULT}"
export GOPATH="${GOPATH:-$HOME/go}"
mkdir -p "$GOBIN" "$GOPATH"

if ! echo "$PATH" | grep -q "$GOBIN"; then
  info "Adding $GOBIN to PATH for this session."
  info "To persist, add: export PATH=\$PATH:$GOBIN  to your ~/.bashrc or ~/.zshrc"
  export PATH="$PATH:$GOBIN"
fi

info "Installing Go-based tools (this can take time)..."
for mod in "${GOMODTOOLS[@]}"; do
  binname=$(echo "$mod" | sed -E 's#.*/([^/@]+).*#\1#')
  if command_exists "$binname"; then
    ok "Skipping $binname — already on PATH."
    continue
  fi
  info "go install $mod ..."
  if ! GO111MODULE=on go install "$mod" 2>/dev/null; then
    warn "go install failed for $mod — install manually if needed."
  fi
done

# massdns — must be built from source
if [ ! -x "/usr/local/bin/massdns" ]; then
  info "Cloning and building massdns..."
  if [ -d "$TOOLS_DIR/massdns" ]; then
    (cd "$TOOLS_DIR/massdns" && git pull) || warn "git pull failed for massdns."
  else
    git clone https://github.com/blechschmidt/massdns.git "$TOOLS_DIR/massdns" \
      || warn "Failed to clone massdns."
  fi
  if [ -d "$TOOLS_DIR/massdns" ]; then
    (cd "$TOOLS_DIR/massdns" && make) || warn "make failed for massdns (missing dev libs?)."
    if [ -f "$TOOLS_DIR/massdns/bin/massdns" ]; then
      sudo cp -f "$TOOLS_DIR/massdns/bin/massdns" /usr/local/bin/ \
        || warn "Failed to copy massdns to /usr/local/bin."
    fi
  fi
else
  ok "massdns already installed at /usr/local/bin/massdns."
fi

###############################
# 5. ctfr.py — built-in module
###############################
info "Verifying ctfr.py (built-in v1.3 module)..."
if [ -f "./ctfr.py" ]; then
  ok "ctfr.py found. No separate install needed — it ships with the dashboard."
  info "Dashboard uses: python3 ctfr.py -d <domain> --no-banner"
else
  warn "ctfr.py not found in current directory."
  warn "Ensure ctfr.py is present alongside app.py before starting the server."
fi

###############################
# 6. Clonable tools (interactive)
###############################
echo ""
echo "------------------------------------------------------"
echo "  Clonable Tools (optional)"
echo "  These match the clone_url entries in data.json."
echo "  Options: all | skip | comma-separated numbers (e.g. 1,3,5)"
echo "------------------------------------------------------"
idx=0
for entry in "${CLONABLE_TOOLS[@]}"; do
  idx=$((idx+1))
  display_name="${entry%%|*}"
  echo "  $idx) $display_name"
done
echo ""
read -r -p "Your choice [all/skip/1,2,...]: " clone_choice

selected_clone_indices=()
if [[ "${clone_choice:-}" =~ ^([Aa][Ll][Ll])$ ]]; then
  for i in $(seq 0 $(( ${#CLONABLE_TOOLS[@]} - 1 ))); do
    selected_clone_indices+=("$i")
  done
elif [[ ! "${clone_choice:-}" =~ ^([Ss][Kk][Ii][Pp])$ ]]; then
  IFS=', ' read -r -a raw_indices <<< "$clone_choice"
  for i in "${raw_indices[@]}"; do
    if [[ "$i" =~ ^[0-9]+$ ]] && [ "$i" -ge 1 ] && [ "$i" -le "${#CLONABLE_TOOLS[@]}" ]; then
      selected_clone_indices+=("$(( i - 1 ))")
    else
      warn "Ignoring invalid selection: $i"
    fi
  done
fi

if [ ${#selected_clone_indices[@]} -gt 0 ]; then
  for idx in "${selected_clone_indices[@]}"; do
    IFS='|' read -r display_name target_dir clone_url post_cmd <<< "${CLONABLE_TOOLS[$idx]}"

    if [ -d "$target_dir" ]; then
      echo ""
      echo "  Directory exists: $target_dir"
      read -r -p "  [ri] Reinstall (rm + clone)  [up] Update (git pull)  [ig] Ignore: " dir_choice
      case "${dir_choice:-ig}" in
        ri) rm -rf "$target_dir"; info "Removed $target_dir." ;;
        up) (cd "$target_dir" && git pull) || warn "git pull failed for $display_name."; continue ;;
        *)  info "Ignoring existing $target_dir."; continue ;;
      esac
    fi

    info "Cloning $display_name → $target_dir ..."
    if git clone "$clone_url" "$target_dir"; then
      ok "Cloned $display_name."
      if [ -n "$post_cmd" ]; then
        info "Running post-install for $display_name..."
        (cd "$target_dir" && eval "$post_cmd") \
          || warn "Post-install failed for $display_name — check manually."
      fi
    else
      warn "Failed to clone $display_name from $clone_url"
    fi
  done
else
  info "Skipping all clonable tools."
fi

###############################
# 7. Optional API key setup
###############################
echo ""
echo "------------------------------------------------------"
echo "  Optional: API key setup"
echo "------------------------------------------------------"

# Shodan
if command_exists shodan; then
  read -r -p "Run 'shodan init' now? (requires API key) (y/N): " shchoice
  if [[ "${shchoice:-}" =~ ^[Yy]$ ]]; then
    read -r -p "  Shodan API key: " SHODAN_KEY
    shodan init "$SHODAN_KEY" || warn "shodan init failed — run 'shodan init <KEY>' manually."
  fi
fi

# GHunt cookie setup reminder
if [ -d "${TOOLS_DIR}/GHunt" ]; then
  echo ""
  warn "GHunt requires a cookie generation step before first use:"
  echo "    cd ${TOOLS_DIR}/GHunt && python3 check_and_gen_cookies.py"
fi

###############################
# 8. Verify key binaries
###############################
echo ""
info "Checking expected binaries..."
EXPECTED_BINS=(
  # Go tools
  subfinder httpx nuclei amass gau gauplus assetfinder dnsx httprobe dalfox trufflehog
  # System tools
  nmap ffuf gobuster dirb nikto sqlmap hydra medusa ncrack
  hashcat john crunch cewl commix
  aircrack-ng steghide binwalk foremost
  sslscan openssl tcpdump fping hping3 snmpwalk
  ltrace strace jq curl
  # Python tools (in venv)
  wafw00f arjun wfuzz sslyze fierce dnstwist socialscan hashid
)
missing_bins=()
for b in "${EXPECTED_BINS[@]}"; do
  if ! command_exists "$b"; then
    missing_bins+=("$b")
  fi
done

if [ ${#missing_bins[@]} -gt 0 ]; then
  warn "The following expected binaries are NOT on PATH:"
  for b in "${missing_bins[@]}"; do
    echo "    - $b"
  done
  echo ""
  warn "This may be normal for tools installed only inside the venv."
  warn "Activate the venv first: source ${VENV_DIR}/bin/activate"
  warn "Go tools: ensure $GOBIN is in your PATH permanently."
else
  ok "All expected binaries found."
fi

###############################
# 9. data.json — shell=False notice
###############################
echo ""
info "IMPORTANT — shell=False notice:"
echo "  app.py executes all commands with shell=False (shlex-based splitting)."
echo "  Pipe characters ( | ) and shell redirects ( > / >> ) in command templates"
echo "  are passed LITERALLY and will NOT be interpreted by a shell."
echo ""
echo "  Affected built-in tools in data.json:"
echo "    - crt-sh-builtin  (uses: curl ... | jq ...)"
echo "    - waybackurls     (uses: echo ... | waybackurls)"
echo "    - openssl-cert    (uses: echo | openssl ... | openssl ...)"
echo ""
echo "  To fix these, either:"
echo "    a) Replace them with the ctfr.py / direct API equivalents, OR"
echo "    b) Add a custom handler in app.py's CUSTOM_HANDLERS dict, OR"
echo "    c) Wrap the command in a small shell script and call that instead."
echo ""
echo "  Also: tools using custom handlers (e.g. ffuf-file-finder) must have"
echo "  \"custom_handling\": true set in their data.json entry."

###############################
# Summary
###############################
echo ""
echo "======================================================"
echo "  OSINTel Dashboard v3.0 — Setup Complete"
echo "======================================================"
echo ""
echo "  Python venv : ${VENV_DIR}"
echo "  Tools dir   : ${TOOLS_DIR}"
echo "  Data dir    : ${DATA_DIR}"
echo "  GOBIN       : ${GOBIN}"
echo "  massdns     : $( [ -x /usr/local/bin/massdns ] && echo 'installed' || echo 'NOT installed' )"
echo ""
echo "  Next steps:"
echo "    1) source ${VENV_DIR}/bin/activate"
echo "    2) python3 app.py"
echo "    3) Open http://localhost:5001 in your browser"
echo ""
echo "  Environment overrides:"
echo "    PORT=8080 HOST=127.0.0.1 FLASK_DEBUG=1 python3 app.py"
echo ""
echo "  Manual steps still required:"
echo "    - GHunt : cd ${TOOLS_DIR}/GHunt && python3 check_and_gen_cookies.py"
echo "    - Shodan: shodan init <API_KEY>"
echo "    - Add your AbuseIPDB / VT / other API keys directly in the tool"
echo "      input fields when running each tool from the dashboard."
echo ""
echo "  ⚠  Use only on infrastructure you own or have explicit permission to test."
echo "======================================================"