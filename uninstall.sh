#!/usr/bin/env bash
# uninstall.sh — OSINTel Dashboard v3.0 removal script
# Removes project files, Go binaries, and optionally apt packages.
#
# Usage:
#   chmod +x uninstall.sh && ./uninstall.sh
#
# Flags:
#   --full     Also removes apt packages installed by setup.sh.
#              WARNING: these may be used by other tools on your system.
#   --purge    Like --full but also runs apt purge + autoremove.
#
# Run from INSIDE the OSINTel-Dashboard directory.

set -o pipefail
set -o nounset

###############################
# Flags
###############################
FULL_REMOVE=false
PURGE=false

for arg in "$@"; do
  case "$arg" in
    --full)  FULL_REMOVE=true ;;
    --purge) FULL_REMOVE=true; PURGE=true ;;
    *)       echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

###############################
# Configuration — must match setup.sh
###############################
VENV_DIR="./venv"
TOOLS_DIR="./tools"
DATA_DIR="./data"
GOBIN="${GOBIN:-$HOME/go/bin}"

# Go binaries installed by setup.sh
GO_BINS=(
  amass
  subfinder
  assetfinder
  dnsx
  waybackurls
  gau
  gauplus
  hakrawler
  httprobe
  httpx
  nuclei
  subjack
  dalfox
  trufflehog
)

# apt packages installed by setup.sh
# Shown for confirmation — only removed with --full / --purge
APT_PACKAGES=(
  # DNS / network recon
  nmap whois dnsutils dnsrecon dnsenum
  traceroute mtr
  # Network tools
  netcat-openbsd socat fping hping3
  netstat-nat net-tools
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
  sslscan
  # File utilities
  jq ripgrep poppler-utils
  # Other
  masscan zmap smbclient
  # Optional (installed if available on apt)
  recon-ng enum4linux wpscan joomscan spiderfoot
)

# System-wide pip packages installed by setup.sh
PIP_SYSTEM_PACKAGES=(
  holehe
)

###############################
# Helpers
###############################
warn()    { echo -e "\e[33m[WARN]\e[0m $*"; }
info()    { echo -e "\e[36m[INFO]\e[0m $*"; }
ok()      { echo -e "\e[32m[ OK ]\e[0m $*"; }
removed() { echo -e "\e[31m[DEL ]\e[0m $*"; }
skip()    { echo -e "\e[90m[SKIP]\e[0m $*"; }

confirm() {
  # confirm "message" → returns 0 (yes) or 1 (no)
  read -r -p "$1 (y/N): " _ans
  [[ "${_ans:-}" =~ ^[Yy]$ ]]
}

###############################
# Banner
###############################
echo ""
echo -e "\e[31m  ___  ____ ___ _   _ _____      _\e[0m"
echo -e "\e[31m / _ \\/ ___|_ _| \\ | |_   _|__ _| |\e[0m"
echo -e "\e[31m| | | \\___ \\| ||  \\| | | |/ _\` | |\e[0m"
echo -e "\e[31m| |_| |___) | || |\\  | | | (_| | |\e[0m"
echo -e "\e[31m \\___/|____/___|_| \\_| |_|\\__,_|_|\e[0m"
echo ""
echo "  OSINTel Dashboard — Uninstall Script v3.0"
echo ""
if $FULL_REMOVE && $PURGE; then
  echo -e "  Mode: \e[31mFULL PURGE\e[0m — project files + Go binaries + apt purge + autoremove"
elif $FULL_REMOVE; then
  echo -e "  Mode: \e[33mFULL\e[0m — project files + Go binaries + apt remove"
else
  echo -e "  Mode: \e[36mSOFT\e[0m — project files + Go binaries only (apt packages kept)"
  echo "  Use --full or --purge to also remove apt packages."
fi
echo ""
echo "  ⚠  This cannot be undone. Saved output files in data/ will be deleted."
echo "------------------------------------------------------"
echo ""

confirm "Proceed with uninstall?" || { echo "Aborted."; exit 0; }
echo ""

###############################
# 1. Kill any running app.py process
###############################
info "Checking for running app.py processes..."
if pgrep -f "python3 app.py" >/dev/null 2>&1; then
  warn "app.py is currently running."
  if confirm "  Kill running app.py process?"; then
    pkill -f "python3 app.py" && ok "Process killed." || warn "Could not kill process — stop it manually."
  else
    warn "Skipping — you may need to stop app.py manually before files can be removed."
  fi
else
  ok "No running app.py process found."
fi
echo ""

###############################
# 2. Project directories
###############################
info "Removing project directories..."

# venv
if [ -d "$VENV_DIR" ]; then
  rm -rf "$VENV_DIR"
  removed "Removed: $VENV_DIR"
else
  skip "$VENV_DIR not found."
fi

# tools/ (cloned repos)
if [ -d "$TOOLS_DIR" ]; then
  confirm "  Remove $TOOLS_DIR/ (all cloned tool repos)?" && {
    rm -rf "$TOOLS_DIR"
    removed "Removed: $TOOLS_DIR"
  } || skip "Kept: $TOOLS_DIR"
else
  skip "$TOOLS_DIR not found."
fi

# data/ (saved output files)
if [ -d "$DATA_DIR" ]; then
  confirm "  Remove $DATA_DIR/ (all saved tool output files)?" && {
    rm -rf "$DATA_DIR"
    removed "Removed: $DATA_DIR"
  } || skip "Kept: $DATA_DIR"
else
  skip "$DATA_DIR not found."
fi

# massdns system binary
if [ -x "/usr/local/bin/massdns" ]; then
  confirm "  Remove /usr/local/bin/massdns?" && {
    sudo rm -f /usr/local/bin/massdns
    removed "Removed: /usr/local/bin/massdns"
  } || skip "Kept: /usr/local/bin/massdns"
fi

echo ""

###############################
# 3. JSON state files
###############################
info "Removing JSON state files..."
for f in data.json history.json; do
  if [ -f "./$f" ]; then
    confirm "  Remove ./$f?" && {
      rm -f "./$f"
      removed "Removed: ./$f"
    } || skip "Kept: ./$f"
  else
    skip "./$f not found."
  fi
done
echo ""

###############################
# 4. Go binaries
###############################
info "Removing Go binaries from $GOBIN ..."
removed_go=0
for bin in "${GO_BINS[@]}"; do
  target="$GOBIN/$bin"
  if [ -f "$target" ]; then
    rm -f "$target"
    removed "Removed: $target"
    removed_go=$((removed_go + 1))
  else
    skip "$bin not found in $GOBIN"
  fi
done

# massdns Go cache (if any)
if [ -d "$HOME/go/pkg/mod/github.com/blechschmidt" ]; then
  rm -rf "$HOME/go/pkg/mod/github.com/blechschmidt"
  removed "Removed: Go module cache for massdns"
fi

ok "$removed_go Go binaries removed."
echo ""

###############################
# 5. System-wide pip packages
###############################
info "Removing system-wide pip packages: ${PIP_SYSTEM_PACKAGES[*]} ..."
if command -v pip3 >/dev/null 2>&1; then
  for pkg in "${PIP_SYSTEM_PACKAGES[@]}"; do
    if pip3 show "$pkg" >/dev/null 2>&1; then
      sudo pip3 uninstall -y "$pkg" --break-system-packages 2>/dev/null \
        && removed "pip3 uninstalled: $pkg" \
        || warn "pip3 uninstall failed for $pkg — remove manually if needed."
    else
      skip "$pkg not installed system-wide."
    fi
  done
else
  skip "pip3 not found — skipping system-wide pip removal."
fi
echo ""

###############################
# 6. apt packages (--full / --purge only)
###############################
if $FULL_REMOVE; then
  echo "------------------------------------------------------"
  warn "APT PACKAGE REMOVAL"
  warn "The following packages were installed by setup.sh."
  warn "They may also be used by OTHER tools on your system."
  warn "Review the list carefully before confirming."
  echo ""
  for pkg in "${APT_PACKAGES[@]}"; do
    echo "    $pkg"
  done
  echo ""

  if confirm "  Remove ALL of the above apt packages?"; then
    if $PURGE; then
      info "Running apt purge..."
      sudo apt purge -y "${APT_PACKAGES[@]}" 2>/dev/null || warn "Some packages may not have been installed — continuing."
      info "Running apt autoremove..."
      sudo apt autoremove -y
      ok "apt purge + autoremove complete."
    else
      info "Running apt remove..."
      sudo apt remove -y "${APT_PACKAGES[@]}" 2>/dev/null || warn "Some packages may not have been installed — continuing."
      ok "apt remove complete."
    fi
  else
    skip "apt packages kept."
  fi
  echo ""
else
  info "Skipping apt package removal (use --full or --purge to remove)."
  echo ""
fi

###############################
# 7. Offer to remove the project folder itself
###############################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "------------------------------------------------------"
info "Project directory: $SCRIPT_DIR"
warn "This will delete app.py, ctfr.py, index.html, setup.sh, uninstall.sh, and all remaining files."
echo ""
if confirm "  Delete the entire project directory ($SCRIPT_DIR)?"; then
  # Move out first so we don't rm -rf ourselves mid-execution
  PARENT_DIR="$(dirname "$SCRIPT_DIR")"
  PROJECT_NAME="$(basename "$SCRIPT_DIR")"
  cd "$PARENT_DIR" || exit 1
  rm -rf "$PROJECT_NAME"
  removed "Removed: $SCRIPT_DIR"
  echo ""
  echo "======================================================"
  ok "OSINTel Dashboard fully removed."
  echo "======================================================"
else
  skip "Project directory kept."
  echo ""
  echo "======================================================"
  ok "Uninstall complete. Project directory retained."
  echo ""
  echo "  Kept:  $SCRIPT_DIR"
  echo "  venv, tools/, data/, Go binaries, and pip packages removed."
  echo "======================================================"
fi