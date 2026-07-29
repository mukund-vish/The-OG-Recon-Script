#!/usr/bin/env bash

set -e

# Script Defaults
script="og-recon.sh"
install_path="/usr/local/bin/og-recon"


# Checking for root 
if [[ $EUID -ne 0 ]]; then
    echo -e "${red}Please run this installer as root (sudo ./install.sh)${reset}"
    exit 1
fi

# Detecting Package Manager
PKG_MANAGER=""

PKG_MANAGER=""
if command -v nixos-version &>/dev/null || [[ -f /etc/NIXOS ]]; then
    PKG_MANAGER="nix"
elif command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt"
elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
elif command -v pacman &>/dev/null; then
    PKG_MANAGER="pacman"
elif command -v zypper &>/dev/null; then
    PKG_MANAGER="zypper"
elif command -v apk &>/dev/null; then
    PKG_MANAGER="apk"
else
    echo -e "${red}Could not detect a supported package manager (apt/dnf/yum/pacman/zypper/apk/nix).${reset}"
    echo -e "${red}Please install dependencies manually: nmap, amass, golang, python3, git, toilet, whois, dnsutils/bind-tools${reset}"
    exit 1
fi

echo -e "${blue}Detected package manager: $PKG_MANAGER${reset}"

# Package Installation Function 

install_packages() {
	case "$PKG_MANAGER" in
	nix)
    NIX_USR="${SUDO_USER:-$USER}"
    if [[ "$NIX_USR" == "root" ]]; then
        echo -e "${yellow}Running as root with no SUDO_USER detected — installing into root's nix profile.${reset}"
    fi
    echo -e "${yellow}NixOS detected: installing packages into ${NIX_USR}'s nix profile.${reset}"
    echo -e "${yellow}For a fully declarative setup instead, add these to environment.systemPackages${reset}"
    echo -e "${yellow}in /etc/nixos/configuration.nix: nmap amass go python3 git toilet whois bind${reset}"

    sudo -i -u "$NIX_USR" nix profile install \
        nixpkgs#nmap \
        nixpkgs#amass \
        nixpkgs#go \
        nixpkgs#gcc \
        nixpkgs#toilet \
        nixpkgs#whois \
        nixpkgs#bind \
        nixpkgs#python3Packages.pip \
        nixpkgs#python3 \
        nixpkgs#git 
    AMASS_VIA_GO=0
    ;;
    apt)
        apt-get update -y
        apt-get install -y nmap golang-go python3 python3-pip git toilet whois dnsutils
        if ! apt-get install -y amass; then #attempting direct AMASS Install 
                echo -e "${yellow}amass not available via apt, will install via go instead${reset}"
                AMASS_VIA_GO=1 # go fallback for amass
            fi
    ;;
    dnf)
            dnf install -y nmap golang python3 python3-pip git toilet whois bind-utils
            if ! dnf install -y amass; then
                echo -e "${yellow}amass not available via dnf, will install via go instead${reset}"
                AMASS_VIA_GO=1
            fi
            ;;
    yum)
            yum install -y epel-release || true
            yum install -y nmap golang python3 python3-pip git toilet whois bind-utils
            AMASS_VIA_GO=1
            ;;
    pacman)
            pacman -Sy --noconfirm nmap go python python-pip git toilet whois bind-tools
            if ! pacman -S --noconfirm amass; then
                echo -e "${yellow}amass not available via pacman, will install via go instead${reset}"
                AMASS_VIA_GO=1
            fi
            ;;
    zypper)
            zypper --non-interactive install nmap go python3 python3-pip git toilet whois bind-utils
            AMASS_VIA_GO=1
            ;;
    apk)
            apk update
            apk add nmap go python3 py3-pip git toilet whois bind-tools
            AMASS_VIA_GO=1
            ;;
    esac
}
 
echo -e "${green}Installing dependencies.....${reset}"
install_packages

# Setting up Go environment

if ! command -v go &>/dev/null; then
    echo -e "${red}Go installation failed or 'go' not found on PATH. Aborting.${reset}"
    exit 1
fi

GOPATH_BIN="$(go env GOPATH)/bin"
export PATH="$PATH:$GOPATH_BIN"

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(eval echo "~$TARGET_USER")

for rcfile in "$TARGET_HOME/.bashrc" "$TARGET_HOME/.zshrc"; do
    if [[ -f "$rcfile" ]] && ! grep -q "$GOPATH_BIN" "$rcfile"; then
        if ! echo "export PATH=\$PATH:$GOPATH_BIN" >> "$rcfile" 2>/dev/null; then
            echo -e "${yellow}Could not write to $rcfile (read-only — likely managed by home-manager/Nix).${reset}"
            echo -e "${yellow}Add this to your home-manager config instead: programs.bash.sessionVariables.PATH or home.sessionPath = [ \"$GOPATH_BIN\" ];${reset}"
        fi
    fi
done

# Installing Go-based tools

echo -e "${green}Installing subfinder.....${reset}"
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
 
echo -e "${green}Installing httprobe.....${reset}"
go install -v github.com/tomnomnom/httprobe@latest
 
echo -e "${green}Installing assetfinder.....${reset}"
go install -v github.com/tomnomnom/assetfinder@latest
 
if [[ "$AMASS_VIA_GO" == "1" ]]; then
    echo -e "${green}Installing amass via go.....${reset}"
    go install -v github.com/owasp-amass/amass/v4/...@master
fi

if [[ "$PKG_MANAGER" == "nix" ]]; then
    echo -e "${yellow}Skipping binary copy step on NixOS — Nix profile directories are read-only.${reset}"
    echo -e "${yellow}Binaries remain available via \$GOPATH_BIN ($GOPATH_BIN), which is already on PATH for this session.${reset}"
else
    mkdir -p /usr/local/bin
    for bin in subfinder httprobe assetfinder amass; do
        if [[ -f "$GOPATH_BIN/$bin" ]]; then
            cp -f "$GOPATH_BIN/$bin" /usr/local/bin/
        fi
    done
fi
# paramspider installation

echo -e "${green}Installing paramspider.....${reset}"
PARAMSPIDER_DIR="/opt/paramspider"
if [[ -d "$PARAMSPIDER_DIR" ]]; then
    echo -e "${yellow}paramspider already present at $PARAMSPIDER_DIR, pulling latest.....${reset}"
    git -C "$PARAMSPIDER_DIR" pull
else
    git clone https://github.com/devanshbatham/paramspider "$PARAMSPIDER_DIR"
fi
 
if command -v pip3 &>/dev/null; then
    if ! pip3 install "$PARAMSPIDER_DIR" --break-system-packages 2>/dev/null; then
        if ! pip3 install "$PARAMSPIDER_DIR" 2>/dev/null; then
            echo -e "${yellow}pip3 refused a global install (externally-managed environment, common on NixOS/newer Debian).${reset}"
            echo -e "${yellow}Install manually in a venv, e.g.: python3 -m venv /opt/paramspider-venv && /opt/paramspider-venv/bin/pip install $PARAMSPIDER_DIR${reset}"
        fi
    fi
else
    echo -e "${yellow}pip3 not found; skipping paramspider python install step. Run it manually if needed.${reset}"
fi

# Verification of installations

echo -e "${blue}Verifying dependencies.....${reset}"
missing=0
for cmd in nmap amass subfinder httprobe assetfinder whois dig toilet paramspider; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${red}[!] Missing: $cmd${reset}"
        missing=1
    fi
done
 
if [[ $missing -eq 1 ]]; then
    echo -e "${yellow}Some tools are missing from PATH. og-recon may still install but some scan stages will fail.${reset}"
fi

# Final Phase : Installing OG-Recon Script

echo -e "${green}Installing og-recon.....${reset}"
if [[ ! -f "$script" ]]; then
    echo -e "${red}Could not find $script in the current directory. Aborting.${reset}"
    exit 1
fi
 
cp "$script" "$install_path"
chmod +x "$install_path"
 
if [[ -f "$install_path" && -x "$install_path" ]]; then
    echo -e "${green}Installation Complete! You can use it now: og-recon domain.com${reset}"
else
    echo -e "${red}Installation Failed. Please check your permissions.${reset}"
    exit 1
fi