#!/bin/bash

set -euo pipefail

readonly LOG_FILE="/var/log/setup-server.log"
readonly CONFIG_DIR="$HOME/.xenz"
readonly PROJECT_FILE="$CONFIG_DIR/project"
readonly BACKUP_DIR="$CONFIG_DIR/backups"

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

check_root
check_internet
check_disk_space

mkdir -p "$CONFIG_DIR" "$BACKUP_DIR"
touch "$LOG_FILE"

log_info "Starting server setup..."

log_info "Updating package lists..."
apt update -y >/dev/null 2>&1 &
progress $! "Package lists updated"

log_info "Installing base packages..."
apt install -y ca-certificates curl gnupg lsb-release software-properties-common ufw fail2ban htop >/dev/null 2>&1 &
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
    echo -e "  ${BLUE}Logs:${NC} $LOG_FILE"
    echo ""
}
trap final_summary EXIT

sudo tee /usr/local/bin/xenz > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

readonly CONFIG_DIR="$HOME/.xenz"
readonly PROJECT_FILE="$CONFIG_DIR/project"
readonly BACKUP_DIR="$CONFIG_DIR/backups"
readonly LOG_FILE="$CONFIG_DIR/xenz.log"
readonly GITHUB_USER="FarshadGhanbari"
readonly EMAIL="eng.ghanbari2025@gmail.com"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

mkdir -p "$CONFIG_DIR" "$BACKUP_DIR"
touch "$LOG_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
    log "INFO: $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
    log "SUCCESS: $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
    log "ERROR: $*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
    log "WARN: $*"
}

validate_domain() {
    [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] || return 1
}

validate_project() {
    [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
}

get_project() {
    [[ -f "$PROJECT_FILE" ]] && cat "$PROJECT_FILE" || return 1
}

get_project_dir() {
    local project=$(get_project) || return 1
    echo "$HOME/$project"
}

backup_project() {
    local project=$(get_project) || { log_error "No project found"; return 1; }
    local project_dir="$HOME/$project"
    [[ -d "$project_dir" ]] || { log_error "Project directory not found"; return 1; }
    local backup_name="backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    log_info "Creating backup: $backup_name"
    tar -czf "$BACKUP_DIR/$backup_name" -C "$HOME" "$project" 2>/dev/null && log_success "Backup created: $backup_name" || { log_error "Backup failed"; return 1; }
}

restore_backup() {
    shopt -s nullglob
    local backups=("$BACKUP_DIR"/*.tar.gz)
    shopt -u nullglob
    [[ ${#backups[@]} -gt 0 ]] || { log_error "No backups found"; return 1; }
    echo -e "${CYAN}Available backups:${NC}"
    echo ""
    local i=1
    local backup_list=()
    for backup in "${backups[@]}"; do
        [[ -f "$backup" ]] || continue
        local size=$(du -h "$backup" 2>/dev/null | cut -f1 || echo "N/A")
        local date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1 || stat -f %Sm -t "%Y-%m-%d" "$backup" 2>/dev/null || ls -l "$backup" 2>/dev/null | awk '{print $6, $7, $8}' || echo "N/A")
        echo -e "  ${BLUE}$i)${NC} $(basename "$backup") - ${YELLOW}$size${NC} - ${CYAN}$date${NC}"
        backup_list+=("$backup")
        ((i++))
    done
    [[ ${#backup_list[@]} -eq 0 ]] && { log_error "No valid backups found"; return 1; }
    echo ""
    PS3="Select backup to restore: "
    select backup in "${backup_list[@]}" "Cancel"; do
        [[ "$backup" == "Cancel" ]] && { PS3=""; return 0; }
        [[ -z "$backup" ]] && { log_error "Invalid selection"; PS3=""; return 1; }
        [[ -f "$backup" ]] || { log_error "Backup file not found"; PS3=""; return 1; }
        read -rp "Restore from $(basename "$backup")? (y/N): " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { PS3=""; return 0; }
        log_info "Restoring from: $(basename "$backup")"
        tar -xzf "$backup" -C "$HOME" && log_success "Backup restored successfully" || { log_error "Restore failed"; PS3=""; return 1; }
        PS3=""
        break
    done
}

list_backups() {
    shopt -s nullglob
    local backups=("$BACKUP_DIR"/*.tar.gz)
    shopt -u nullglob
    [[ ${#backups[@]} -gt 0 ]] || { log_info "No backups found"; return 1; }
    echo -e "${CYAN}=== Backup List ===${NC}"
    echo ""
    local total_size=0
    local count=0
    for backup in "${backups[@]}"; do
        [[ -f "$backup" ]] || continue
        local size=$(du -b "$backup" 2>/dev/null | cut -f1 || echo "0")
        local size_h=$(du -h "$backup" 2>/dev/null | cut -f1 || echo "N/A")
        local date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1 || stat -f %Sm -t "%Y-%m-%d %H:%M" "$backup" 2>/dev/null || ls -l "$backup" 2>/dev/null | awk '{print $6, $7, $8}' || echo "N/A")
        echo -e "  ${BLUE}$(basename "$backup")${NC}"
        echo -e "    Size: ${YELLOW}$size_h${NC} | Date: ${CYAN}$date${NC}"
        total_size=$((total_size + size))
        ((count++))
    done
    echo ""
    local total_size_mb=$((total_size / 1024 / 1024))
    local total_size_gb=$((total_size / 1024 / 1024 / 1024))
    local total_size_h
    if [[ $total_size_gb -gt 0 ]]; then
        total_size_h="${total_size_gb}GB"
    elif [[ $total_size_mb -gt 0 ]]; then
        total_size_h="${total_size_mb}MB"
    else
        total_size_h="$((total_size / 1024))KB"
    fi
    echo -e "Total: ${GREEN}$count${NC} backups | ${GREEN}$total_size_h${NC}"
}

delete_all_backups() {
    shopt -s nullglob
    local backups=("$BACKUP_DIR"/*.tar.gz)
    shopt -u nullglob
    [[ ${#backups[@]} -gt 0 ]] || { log_info "No backups found"; return 0; }
    local count=0
    local total_size=0
    for backup in "${backups[@]}"; do
        [[ -f "$backup" ]] || continue
        local size=$(du -b "$backup" 2>/dev/null | cut -f1 || echo "0")
        total_size=$((total_size + size))
        ((count++))
    done
    local total_size_mb=$((total_size / 1024 / 1024))
    local total_size_gb=$((total_size / 1024 / 1024 / 1024))
    local total_size_h
    if [[ $total_size_gb -gt 0 ]]; then
        total_size_h="${total_size_gb}GB"
    elif [[ $total_size_mb -gt 0 ]]; then
        total_size_h="${total_size_mb}MB"
    else
        total_size_h="$((total_size / 1024))KB"
    fi
    echo -e "${YELLOW}⚠${NC} This will delete ${RED}ALL${NC} backups:"
    echo -e "  - ${RED}$count${NC} backup files"
    echo -e "  - Total size: ${RED}$total_size_h${NC}"
    echo ""
    read -rp "Are you sure? Type 'DELETE' to confirm: " confirm
    [[ "$confirm" != "DELETE" ]] && { log_info "Operation cancelled"; return 0; }
    log_info "Deleting all backups..."
    local deleted=0
    for backup in "${backups[@]}"; do
        [[ -f "$backup" ]] || continue
        rm -f "$backup" && ((deleted++)) || log_warn "Failed to delete: $(basename "$backup")"
    done
    [[ $deleted -gt 0 ]] && log_success "Deleted $deleted backup(s). Freed $total_size_h" || log_warn "No backups deleted"
}

health_check() {
    local project_dir=$(get_project_dir) || return 1
    cd "$project_dir" || return 1
    log_info "Checking Docker containers..."
    docker compose -f prod.docker-compose.yml ps
    log_info "Checking container health..."
    docker compose -f prod.docker-compose.yml ps --format json | jq -r '.[] | "\(.Name): \(.Health // "N/A")"' 2>/dev/null || docker compose -f prod.docker-compose.yml ps
}

show_logs() {
    local project_dir=$(get_project_dir) || return 1
    cd "$project_dir" || return 1
    read -rp "Enter container name (or 'all'): " container
    if [[ "$container" == "all" ]]; then
        docker compose -f prod.docker-compose.yml logs --tail=100 -f
    else
        docker compose -f prod.docker-compose.yml logs --tail=100 -f "$container"
    fi
}

show_stats() {
    echo -e "${CYAN}=== System Statistics ===${NC}"
    echo -e "${BLUE}Disk Usage:${NC}"
    df -h / | tail -1
    echo -e "${BLUE}Memory Usage:${NC}"
    free -h
    echo -e "${BLUE}Docker Containers:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo -e "${BLUE}Docker Images:${NC}"
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
}

github_auth() {
    gh auth login || { log_error "GitHub authentication failed"; return 1; }
    log_success "GitHub authentication successful"
}

renew_ssl() {
    log_info "Renewing SSL certificates..."
    certbot renew --quiet && log_success "SSL certificates renewed" || { log_error "SSL renewal failed"; return 1; }
}

issue_ssl() {
    read -rp "Enter domain (e.g. example.com): " domain
    [[ -z "$domain" ]] && { log_error "Domain is required"; return 1; }
    validate_domain "$domain" || { log_error "Invalid domain format"; return 1; }
    log_info "Issuing SSL for: $domain"
    certbot certonly --standalone -d "$domain" -d "www.$domain" --agree-tos --email "$EMAIL" --non-interactive && log_success "SSL certificate issued" || { log_error "SSL issuance failed"; return 1; }
}

install_project() {
    read -rp "Enter project name (GitHub repo): " project
    [[ -z "$project" ]] && { log_error "Project name is required"; return 1; }
    validate_project "$project" || { log_error "Invalid project name"; return 1; }
    local project_dir="$HOME/$project"
    [[ -d "$project_dir" ]] && { log_error "Project already exists"; return 1; }
    log_info "Cloning project: $project"
    git clone "https://github.com/$GITHUB_USER/$project.git" "$project_dir" || { log_error "Clone failed"; return 1; }
    cd "$project_dir" || return 1
    echo "$project" > "$PROJECT_FILE"
    log_info "Building and starting containers..."
    docker compose -f prod.docker-compose.yml up -d --build --remove-orphans && log_success "Project installed successfully" || { log_error "Installation failed"; return 1; }
}

update_project() {
    local project=$(get_project) || { log_error "No project found. Install project first."; return 1; }
    local project_dir="$HOME/$project"
    [[ -d "$project_dir" ]] || { log_error "Project directory not found"; return 1; }
    backup_project || log_warn "Backup failed, continuing anyway..."
    cd "$project_dir" || return 1
    log_info "Updating project: $project"
    git pull || { log_error "Git pull failed"; return 1; }
    log_info "Rebuilding containers..."
    docker compose -f prod.docker-compose.yml up -d --build --remove-orphans && log_success "Project updated successfully" || { log_error "Update failed"; return 1; }
}

update_db() {
    local project_dir=$(get_project_dir) || return 1
    read -rp "This will reset the database. Continue? (y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 0
    cd "$project_dir" || return 1
    log_info "Resetting database..."
    docker compose -f prod.docker-compose.yml exec -T laravel php artisan db:fresh-seed && log_success "Database updated" || { log_error "Database update failed"; return 1; }
}

docker_info() {
    docker info
}

cleanup_docker() {
    echo -e "${YELLOW}⚠${NC} This will remove unused Docker resources:"
    echo "  - Stopped containers"
    echo "  - Unused images"
    echo "  - Unused volumes"
    echo "  - Unused networks"
    echo "  - Build cache"
    echo ""
    read -rp "Continue? (y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 0
    
    log_info "Cleaning up Docker resources..."
    
    log_info "Removing stopped containers..."
    docker container prune -f >/dev/null 2>&1 && log_success "Stopped containers removed" || log_warn "No stopped containers"
    
    log_info "Removing unused images..."
    local images_before=$(docker images -q | wc -l)
    docker image prune -af >/dev/null 2>&1
    local images_after=$(docker images -q | wc -l)
    local removed=$((images_before - images_after))
    [[ $removed -gt 0 ]] && log_success "Removed $removed unused images" || log_info "No unused images"
    
    log_info "Removing unused volumes..."
    docker volume prune -f >/dev/null 2>&1 && log_success "Unused volumes removed" || log_warn "No unused volumes"
    
    log_info "Removing unused networks..."
    docker network prune -f >/dev/null 2>&1 && log_success "Unused networks removed" || log_warn "No unused networks"
    
    log_info "Removing build cache..."
    docker builder prune -af >/dev/null 2>&1 && log_success "Build cache removed" || log_warn "No build cache"
    
    log_info "Calculating freed space..."
    local system_df=$(docker system df --format "{{.Size}}" 2>/dev/null | head -1 || echo "0B")
    log_success "Cleanup completed! System usage: $system_df"
}

show_menu() {
    clear
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                                                            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              ${YELLOW}╔═══════════════════════════════╗${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              ${YELLOW}║${NC}                               ${YELLOW}║${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              ${YELLOW}║${NC}         ${BLUE}╔═══╗╔═══╗╔╗   ╔╗╔═══╗${NC}         ${YELLOW}║${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              ${YELLOW}║${NC}         ${BLUE}║╔═╗║║╔═╗║║║   ║║║╔═╗║${NC}         ${YELLOW}║${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              ${YELLOW}║${NC}         ${BLUE}║║ ║║║║ ╚╝║║   ║║║║ ║║${NC}         ${YELLOW}║${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              ${YELLOW}║${NC}         ${BLUE}║║ ║║║║ ╔╗║║   ║║║║ ║║${NC}         ${YELLOW}║${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              ${YELLOW}║${NC}         ${BLUE}║╚═╝║║╚═╝║║╚═╗║╚═╝║╚═╝║${NC}         ${YELLOW}║${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              ${YELLOW}║${NC}         ${BLUE}╚═══╝╚═══╝╚══╝╚═══╝╚═══╝${NC}         ${YELLOW}║${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              ${YELLOW}║${NC}                               ${YELLOW}║${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              ${YELLOW}║${NC}         ${BLUE}Server Management Tool${NC}         ${YELLOW}║${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              ${YELLOW}║${NC}                               ${YELLOW}║${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              ${YELLOW}╚═══════════════════════════════╝${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                            ${CYAN}║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                                            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}┌─ GitHub & SSL${NC}                                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}│${NC}  ${GREEN}1)${NC} GitHub Auth Login                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}│${NC}  ${GREEN}2)${NC} Renew SSL (Certbot)                                 ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}│${NC}  ${GREEN}3)${NC} Issue SSL for Domain                                 ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}└───────────────────────────────────────────────────────────${NC}  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}┌─ Project Management${NC}                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}│${NC}  ${GREEN}4)${NC} Install Project                                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}│${NC}  ${GREEN}5)${NC} Update Project                                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}│${NC}  ${GREEN}6)${NC} Backup Project                                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}│${NC}  ${GREEN}7)${NC} Restore Backup                                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}│${NC}  ${GREEN}8)${NC} List Backups                                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}│${NC}  ${GREEN}9)${NC} Delete All Backups                                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}└───────────────────────────────────────────────────────────${NC}  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}┌─ Database${NC}                                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}│${NC}  ${GREEN}10)${NC} Update DB (Fresh Seed)                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}└───────────────────────────────────────────────────────────${NC}  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}┌─ Monitoring${NC}                                             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}│${NC}  ${GREEN}11)${NC} Health Check                                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}│${NC}  ${GREEN}12)${NC} View Logs                                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}│${NC}  ${GREEN}13)${NC} System Stats                                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}└───────────────────────────────────────────────────────────${NC}  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}┌─ Docker${NC}                                                 ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}│${NC}  ${GREEN}14)${NC} Docker Info                                         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}│${NC}  ${GREEN}15)${NC} View Logs                                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}│${NC}  ${GREEN}16)${NC} Cleanup (Remove unused images/volumes)             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}└───────────────────────────────────────────────────────────${NC}  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                            ${CYAN}║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                                            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}▶${NC}  ${YELLOW}0)${NC} Exit                                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                            ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    read -rp "$(echo -e ${CYAN}Select option${NC} ${YELLOW}[0-16]${NC}${CYAN}:${NC} ) " choice
    case $choice in
        1) github_auth && pause ;;
        2) renew_ssl && pause ;;
        3) issue_ssl && pause ;;
        4) install_project && pause ;;
        5) update_project && pause ;;
        6) backup_project && pause ;;
        7) restore_backup && pause ;;
        8) list_backups && pause ;;
        9) delete_all_backups && pause ;;
        10) update_db && pause ;;
        11) health_check && pause ;;
        12) show_logs ;;
        13) show_stats && pause ;;
        14) docker_info && pause ;;
        15) show_logs ;;
        16) cleanup_docker && pause ;;
        0) echo -e "${GREEN}Goodbye!${NC}" && exit 0 ;;
        *) log_error "Invalid option" && sleep 1 ;;
    esac
}

pause() {
    read -rp "Press Enter to continue..."
}

while true; do
show_menu
done
EOF

sudo chmod +x /usr/local/bin/xenz