#!/bin/bash

set -euo pipefail

readonly LOG_FILE="/var/log/setup-server.log"
readonly CONFIG_DIR="$HOME/.xenz"
readonly PROJECT_FILE="$CONFIG_DIR/project"
readonly BACKUP_DIR="$CONFIG_DIR/backups"
readonly PROXY_FILE="$CONFIG_DIR/proxy"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
    log "INFO" "$*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
    log "SUCCESS" "$*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
    log "WARN" "$*"
}

log_error() {
    echo -e "${RED}✗${NC} Error on line $1. Exit code: $2" >&2
    log "ERROR" "Line $1, Exit code: $2"
}
trap 'log_error $LINENO $?' ERR

check_root() {
    [[ $EUID -eq 0 ]] || { log_error $LINENO 1 "This script must be run as root"; exit 1; }
}

check_disk_space() {
    local available=$(df / | tail -1 | awk '{print $4}')
    local required=5242880
    [[ $available -gt $required ]] || { log_warn "Low disk space. At least 5GB recommended"; return 1; }
}

check_internet() {
    ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || { log_error $LINENO 1 "No internet connection"; exit 1; }
}

progress() {
    local pid=$1
    local msg=$2
    local spin='-\|/'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(((i+1)%4))
        printf "\r${CYAN}${spin:$i:1}${NC} $msg"
        sleep 0.1
    done
    printf "\r${GREEN}✓${NC} $msg\n"
}

install_package() {
    local pkg=$1
    log_info "Installing $pkg..."
    apt install -y "$pkg" >/dev/null 2>&1 &
    progress $! "$pkg installed"
}

clear_git_proxy() {
    git config --global --unset http.proxy 2>/dev/null || true
    git config --global --unset https.proxy 2>/dev/null || true
}

test_proxy() {
    local proxy_url="$1"
    curl --proxy "$proxy_url" -fsSL --connect-timeout 5 --max-time 10 https://github.com -o /dev/null 2>/dev/null
}

apply_proxy_session() {
    local proxy_url="$1"
    export PROXY="$proxy_url"
    export http_proxy="$PROXY"
    export https_proxy="$PROXY"
    export HTTP_PROXY="$PROXY"
    export HTTPS_PROXY="$PROXY"
    export ALL_PROXY="$PROXY"
}

disable_proxy() {
    rm -f "$PROXY_FILE"
    clear_git_proxy
    unset PROXY http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
}

configure_proxy() {
    read -rp "Use proxy on this server? (y/N): " use_proxy
    if [[ "$use_proxy" != "y" && "$use_proxy" != "Y" ]]; then
        disable_proxy
        log_info "Proxy disabled for this server"
        return 0
    fi

    local default_proxy="socks5://ocea:server2025@85.9.99.150:1080"
    read -rp "Enter proxy URL [$default_proxy]: " proxy_value
    proxy_value=${proxy_value:-$default_proxy}

    log_info "Testing proxy connection..."
    if ! test_proxy "$proxy_value"; then
        disable_proxy
        log_warn "Proxy unreachable, continuing without proxy"
        return 0
    fi

    echo "$proxy_value" > "$PROXY_FILE"
    apply_proxy_session "$proxy_value"
    clear_git_proxy
    log_success "Proxy enabled for this server"
}

check_root
check_internet
check_disk_space

mkdir -p "$CONFIG_DIR" "$BACKUP_DIR"
touch "$LOG_FILE"

configure_proxy

log_info "Starting server setup..."

log_info "Updating package lists..."
apt update -y >/dev/null 2>&1 &
progress $! "Package lists updated"

log_info "Installing base packages..."
apt install -y ca-certificates curl gnupg lsb-release software-properties-common ufw fail2ban htop apache2-utils rsync >/dev/null 2>&1 &
progress $! "Base packages installed"

if ! command -v docker >/dev/null 2>&1; then
    log_info "Installing Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    apt update -y >/dev/null 2>&1
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin >/dev/null 2>&1 &
    progress $! "Docker installed"
    usermod -aG docker "$SUDO_USER" 2>/dev/null || true
    log_success "Docker installed successfully"
else
    log_info "Docker already installed"
fi

if ! docker compose version >/dev/null 2>&1; then
    log_info "Installing Docker Compose..."
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p "$DOCKER_CONFIG/cli-plugins"
    curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o "$DOCKER_CONFIG/cli-plugins/docker-compose" &
    progress $! "Docker Compose downloaded"
    chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
    log_success "Docker Compose installed"
else
    log_info "Docker Compose already installed"
fi

if ! docker buildx version >/dev/null 2>&1; then
    log_info "Installing Docker Buildx..."
    mkdir -p ~/.docker/cli-plugins
    curl -fsSL "https://github.com/docker/buildx/releases/latest/download/buildx-$(uname -s)-$(uname -m)" -o ~/.docker/cli-plugins/docker-buildx &
    progress $! "Docker Buildx downloaded"
    chmod +x ~/.docker/cli-plugins/docker-buildx
    log_success "Docker Buildx installed"
else
    log_info "Docker Buildx already installed"
fi

if ! command -v gh >/dev/null 2>&1; then
    install_package gh
    log_success "GitHub CLI installed"
else
    log_info "GitHub CLI already installed"
fi

if ! command -v certbot >/dev/null 2>&1; then
    install_package certbot
    log_success "Certbot installed"
else
    log_info "Certbot already installed"
fi

log_info "Configuring firewall..."
ufw --force enable >/dev/null 2>&1 || true
ufw allow 22/tcp >/dev/null 2>&1
ufw allow 80/tcp >/dev/null 2>&1
ufw allow 443/tcp >/dev/null 2>&1
log_success "Firewall configured"

final_summary() {
    echo ""
    log_success "Installation completed successfully"
    echo ""
    echo -e "${CYAN}Installed Tools:${NC}"
    echo -e "  ${BLUE}Docker:${NC} $(docker --version 2>/dev/null || echo 'not found')"
    echo -e "  ${BLUE}Docker Compose:${NC} $(docker compose version 2>/dev/null || echo 'not found')"
    echo -e "  ${BLUE}Docker Buildx:${NC} $(docker buildx version 2>/dev/null || echo 'not found')"
    echo -e "  ${BLUE}GitHub CLI:${NC} $(gh --version 2>/dev/null | head -n1 || echo 'not found')"
    echo -e "  ${BLUE}Certbot:${NC} $(certbot --version 2>/dev/null || echo 'not found')"
    echo -e "  ${BLUE}Xenz:${NC} Run ${YELLOW}xenz${NC} to open the tool menu"
    echo -e "  ${BLUE}Update xenz later:${NC} ${YELLOW}cd ~/setup-server && git pull && bash setup.sh${NC}"
    echo -e "  ${BLUE}Logs:${NC} $LOG_FILE"
    echo ""
}
trap final_summary EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "$SCRIPT_DIR/xenz.sh" ]]; then
    log_error "xenz.sh not found next to setup.sh ($SCRIPT_DIR/xenz.sh)"
    exit 1
fi

log_info "Installing / updating xenz menu..."
sudo install -m 755 "$SCRIPT_DIR/xenz.sh" /usr/local/bin/xenz
log_success "xenz installed at /usr/local/bin/xenz"
