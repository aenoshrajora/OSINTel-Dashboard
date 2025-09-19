#!/usr/bin/env bash
# setup.sh - OSINTel / Recon workspace setup (v2)
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
)

# System apt packages (base + your requested ones)
APT_PACKAGES=(
  nmap whois dnsutils dnsrecon dnsenum host
  gobuster dirb curl wget
  masscan zmap nikto sqlmap hydra
  smbclient traceroute mtr netcat-openbsd socat
  exiftool poppler-utils binutils jq ripgrep
  python3-pip python3-venv git build-essential make gcc golang
  # recon-ng, enum4linux, metagoofil may be available via apt depending on distro; we check later.
)

# Python packages to install into venv
PYPI_PACKAGES_VENV=(
  Flask
  theHarvester
  ctfr
  sublist3r
  vt-py
  shodan
)

# Python system-wide packages to install (for holehe availability with sudo)
PYPI_PACKAGES_SYSTEM=(
  holehe
)

# Clonable tools list (display name|dir|git url|post-install command)
CLONABLE_TOOLS=(
  "Sherlock|${TOOLS_DIR}/sherlock|https://github.com/sherlock-project/sherlock.git|if [ -f requirements.txt ]; then pip install -r requirements.txt; fi"
  "Sublist3r|${TOOLS_DIR}/Sublist3r|https://github.com/aboul3la/Sublist3r.git|if [ -f requirements.txt ]; then pip install -r requirements.txt; fi"
  "GHunt|${TOOLS_DIR}/GHunt|https://github.com/mxrch/GHunt.git|if [ -f GHunt/requirements.txt ]; then pip install -r GHunt/requirements.txt; fi"
  "Metagoofil|${TOOLS_DIR}/metagoofil|https://github.com/laramies/metagoofil.git|echo 'Metagoofil cloned; no pip requirements auto-installed.'"
)

###############################
# helpers
###############################
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
info() { echo -e "\e[36m[INFO]\e[0m $*"; }
die()  { echo -e "\e[31m[ERR]\e[0m $*"; exit 1; }

###############################
# Start
###############################
echo "--------------------------------------------------"
echo " OSINTel / Recon Setup v2"
echo " Review this script before running on production systems."
echo "--------------------------------------------------"
echo ""

# Confirm
read -r -p "Proceed with installation? This script uses sudo to install packages. (y/N): " proceed
if [[ ! "${proceed:-}" =~ ^[Yy]$ ]]; then
  die "User aborted setup."
fi

# Update apt and install base packages
info "Updating apt package lists..."
sudo apt update -y
sudo apt upgrade -y

info "Installing APT packages (this may take time)..."
sudo apt install -y "${APT_PACKAGES[@]}"

# Some packages may be named differently across distros; try recon-ng, enum4linux, metagoofil via apt if available
if apt-cache show recon-ng >/dev/null 2>&1; then
  info "Installing recon-ng via apt..."
  sudo apt install -y recon-ng || warn "recon-ng apt install failed (you can clone manually)."
else
  warn "recon-ng not available in apt repository; you'll be prompted to clone if desired."
fi

if apt-cache show enum4linux >/dev/null 2>&1; then
  info "Installing enum4linux via apt..."
  sudo apt install -y enum4linux || warn "enum4linux apt install failed."
else
  warn "enum4linux not in apt repo; fallback: you can clone the repo manually."
fi

# Create venv if not exists and activate
if [ ! -d "$VENV_DIR" ]; then
  info "Creating Python virtual environment at $VENV_DIR..."
  python3 -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
# activate venv in current shell for the remainder of the script
# (this won't affect user's interactive shell after script exits)
# but pip installs below will go into this venv
source "${VENV_DIR}/bin/activate"

info "Upgrading pip inside venv..."
pip install --upgrade pip setuptools wheel

# Install Python packages into venv
info "Installing Python packages into venv: ${PYPI_PACKAGES_VENV[*]}"
pip install --break-system-packages "${PYPI_PACKAGES_VENV[@]}" || warn "Some pip installs in venv failed; check output."

# Install system-wide pip packages for tools that must work with sudo/non-sudo (holehe)
info "Installing select Python packages system-wide (so they are available with sudo): ${PYPI_PACKAGES_SYSTEM[*]}"
# Attempt to install via apt-managed pip where available; otherwise use sudo pip3.
if command_exists pip3; then
  sudo pip3 install --break-system-packages "${PYPI_PACKAGES_SYSTEM[@]}" || warn "sudo pip3 install failed for some packages."
else
  warn "pip3 not found for system-wide installs (unexpected)."
fi

# Ensure GO is installed
if ! command_exists go; then
  info "Go not found; attempting to install golang via apt..."
  sudo apt install -y golang || die "Failed to install golang; please install Go manually and re-run this script."
fi

# Ensure GOPATH/GOBIN are set and on PATH
GOBIN_DEFAULT="$HOME/go/bin"
if [ -z "${GOBIN:-}" ]; then
  export GOBIN="$GOBIN_DEFAULT"
fi
if [ -z "${GOPATH:-}" ]; then
  export GOPATH="$HOME/go"
fi
mkdir -p "$GOBIN" "$GOPATH"
if ! echo "$PATH" | grep -q "$GOBIN"; then
  info "Adding $GOBIN to PATH for this session. To persist, add 'export PATH=\$PATH:$GOBIN' to your shell profile."
  export PATH="$PATH:$GOBIN"
fi

# Install go-based tools
info "Installing Go-based tools (this can take time)..."
for mod in "${GOMODTOOLS[@]}"; do
  # extract binary name heuristically (last path element before @)
  binname=$(echo "$mod" | sed -E 's#.*/([^/]+)@.*#\1#')
  if command_exists "$binname"; then
    info "Skipping $binname (already on PATH)."
    continue
  fi
  info "Installing $mod ..."
  # Use 'go install' which places binary into $GOBIN
  if ! GO111MODULE=on go install "$mod"; then
    warn "go install failed for $mod. You can try installing manually."
  fi
done

# Special: massdns clone & build (manual)
if [ ! -x "/usr/local/bin/massdns" ]; then
  info "Cloning and building massdns..."
  mkdir -p "$TOOLS_DIR"
  if [ -d "$TOOLS_DIR/massdns" ]; then
    info "massdns dir exists; attempting to update..."
    (cd "$TOOLS_DIR/massdns" && git pull) || warn "Failed git pull for massdns"
  else
    git clone https://github.com/blechschmidt/massdns.git "$TOOLS_DIR/massdns" || warn "Failed to clone massdns"
  fi
  if [ -d "$TOOLS_DIR/massdns" ]; then
    (cd "$TOOLS_DIR/massdns" && make) || warn "make failed for massdns (missing dev libs?)."
    if [ -f "$TOOLS_DIR/massdns/bin/massdns" ]; then
      sudo cp -f "$TOOLS_DIR/massdns/bin/massdns" /usr/local/bin/ || warn "Failed to copy massdns binary to /usr/local/bin."
    else
      warn "massdns binary not found after build."
    fi
  fi
else
  info "massdns already installed at /usr/local/bin/massdns"
fi

# Ensure commonly used binaries are available (some go-installs may require a new shell to refresh PATH)
info "Checking some expected binaries: subfinder, httpx, httpx, nuclei, amass, gau, gauplus, assetfinder..."
for chk in subfinder httpx nuclei amass gau gauplus assetfinder dnsx httprobe; do
  if ! command_exists "$chk"; then
    warn "$chk not found in PATH. It may be available in $GOBIN ($GOBIN). If not, try re-sourcing your shell or installing manually."
  fi
done

# Clonable tools (interactive)
mkdir -p "$TOOLS_DIR"
echo ""
echo "Clonable tools (optional). These will be cloned into $TOOLS_DIR."
echo "Options: C_all (install all), C_skip (skip), or comma-separated list (C1,C3)."
idx=0
for entry in "${CLONABLE_TOOLS[@]}"; do
  idx=$((idx+1))
  IFS='|' read -r display_dir rest <<< "$entry"
  echo "  C$idx) ${entry%%|*}"
done
echo "  C_all) Install all"
echo "  C_skip) Skip all"
read -r -p "Your choice for clonable tools (e.g., 'C_all', 'C1,C3', 'C_skip'): " clone_choice
selected_clone_indices=()
if [[ "${clone_choice:-}" =~ ^([Cc]_[Aa][Ll][Ll])$ ]]; then
  for i in $(seq 0 $(( ${#CLONABLE_TOOLS[@]} - 1 ))); do selected_clone_indices+=($i); done
elif [[ ! "${clone_choice:-}" =~ ^([Cc]_[Ss][Kk][Ii][Pp])$ ]]; then
  IFS=', ' read -r -a raw_indices <<< "$clone_choice"
  for i in "${raw_indices[@]}"; do
    num_idx=${i#[Cc]}
    if [[ "$num_idx" =~ ^[0-9]+$ ]] && [ "$num_idx" -ge 1 ] && [ "$num_idx" -le ${#CLONABLE_TOOLS[@]} ]; then
      selected_clone_indices+=($((num_idx - 1)))
    else
      warn "Invalid entry ignored: $i"
    fi
  done
fi

if [ ${#selected_clone_indices[@]} -gt 0 ]; then
  echo "Cloning/updating selected tools..."
  for idx in "${selected_clone_indices[@]}"; do
    IFS='|' read -r display target_dir clone_url post_cmd <<< "${CLONABLE_TOOLS[$idx]}"
    display_name=$(echo "$display" | awk -F'(' '{print $1}' | sed 's/ *$//')
    if [ -d "$target_dir" ]; then
      echo "Directory exists for $display_name: $target_dir"
      read -r -p "Options for existing dir: [ri] Reinstall (rm+clone), [up] Update (git pull), [ig] Ignore: " choice
      case "$choice" in
        ri) rm -rf "$target_dir"; echo "Removed $target_dir";;
        up) (cd "$target_dir" && git pull) || warn "git pull failed for $display_name";;
        ig|*) echo "Ignoring existing $target_dir"; continue;;
      esac
    fi
    echo "Cloning $display_name into $target_dir ..."
    if git clone "$clone_url" "$target_dir"; then
      echo "Cloned $display_name."
      if [ -n "$post_cmd" ]; then
        echo "Running post install commands for $display_name..."
        (cd "$target_dir" && eval "$post_cmd") || warn "Post-install command failed for $display_name"
      fi
    else
      warn "Failed to clone $display_name from $clone_url"
    fi
  done
else
  echo "Skipping clonable tools."
fi

# Additional pip installs - shodan init note, vt-py
info "Finalizing Python tooling..."
# shodan already installed in venv earlier; ensure shodan is initialized if user desires
if command_exists shodan; then
  echo ""
  read -r -p "Do you want to run 'shodan init' now? (You must have a Shodan API key) (y/N): " shchoice
  if [[ "${shchoice:-}" =~ ^[Yy]$ ]]; then
    read -r -p "Enter Shodan API key: " SHODAN_KEY
    shodan init "$SHODAN_KEY" || warn "shodan init failed; set key via 'shodan init <API>' manually."
  fi
fi

# SpiderFoot note
if apt-cache show spiderfoot >/dev/null 2>&1; then
  info "Installing spiderfoot via apt..."
  sudo apt install -y spiderfoot || warn "spiderfoot apt install failed."
else
  warn "SpiderFoot not available via apt on this distro. Consider installing it from https://github.com/smicallef/spiderfoot and following its README."
fi

# GHunt / cookie reminder
if [ -d "${TOOLS_DIR}/GHunt" ]; then
  info "If you installed GHunt, run the GHunt cookie generation step manually:"
  echo "  cd ${TOOLS_DIR}/GHunt && python3 check_and_gen_cookies.py"
fi

# holehe root vs non-root note
info "Note: holehe was installed both in venv and system-wide (sudo pip3). This helps it run with/without sudo in some environments."
info "You can test it with: holehe someone@example.com"

# Summarize
echo ""
echo "--------------------------------------------------"
echo "SETUP SUMMARY"
echo " - Python venv located at: ${VENV_DIR}"
echo " - Tools dir: ${TOOLS_DIR}"
echo " - GOBIN: ${GOBIN} (ensure this is in your PATH permanently)"
echo " - Massdns: $( [ -x /usr/local/bin/massdns ] && echo 'installed' || echo 'not installed' )"
echo ""
echo "Recommended next steps:"
echo " 1) Activate venv: source ${VENV_DIR}/bin/activate"
echo " 2) Start the app: python3 app.py"
echo " 3) Use Demo Mode or test targets only. Do NOT scan external targets without authorization."
echo " 4) If any expected binary (subfinder/httpx/nuclei/...) is missing, try re-sourcing your shell or manually re-running 'go install' for that module."
echo ""
echo "Important manual steps:"
echo " - For GHunt: cd ${TOOLS_DIR}/GHunt && python3 check_and_gen_cookies.py"
echo " - For Shodan: shodan init <APIKEY>"
echo " - SpiderFoot: if not installed via apt, install from its GitHub repo."
echo ""
echo "Done. If you saw warnings above, please review them and re-run the relevant step."
echo "--------------------------------------------------"
