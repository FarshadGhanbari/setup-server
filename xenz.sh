#!/bin/bash
set -euo pipefail

readonly CONFIG_DIR="$HOME/.xenz"
readonly PROJECT_FILE="$CONFIG_DIR/project"
readonly BACKUP_DIR="$CONFIG_DIR/backups"
readonly LOG_FILE="$CONFIG_DIR/xenz.log"
readonly PROXY_FILE="$CONFIG_DIR/proxy"
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

load_proxy() {
    if [[ ! -f "$PROXY_FILE" ]]; then
        return 0
    fi

    local proxy_url
    proxy_url=$(<"$PROXY_FILE")
    [[ -n "$proxy_url" ]] || return 0

    if test_proxy "$proxy_url"; then
        apply_proxy_session "$proxy_url"
        log_info "Proxy active"
        return 0
    fi

    log_warn "Proxy configured but unreachable, continuing without proxy"
}

git_cmd() {
    if [[ -n "${PROXY:-}" ]]; then
        git -c http.proxy="$PROXY" -c https.proxy="$PROXY" "$@"
    else
        git "$@"
    fi
}

manage_proxy() {
    if [[ -f "$PROXY_FILE" ]]; then
        echo -e "${BLUE}Current proxy:${NC} $(<"$PROXY_FILE")"
    else
        echo -e "${BLUE}Proxy:${NC} disabled"
    fi
    echo ""
    echo "  1) Enable proxy"
    echo "  2) Disable proxy"
    echo "  3) Test current proxy"
    echo ""
    read -rp "Select option: " proxy_choice
    proxy_choice=$(persian_to_english "$proxy_choice")
    case $proxy_choice in
        1)
            local default_proxy="socks5://ocea:server2025@85.9.99.150:1080"
            read -rp "Enter proxy URL [$default_proxy]: " proxy_value
            proxy_value=${proxy_value:-$default_proxy}
            log_info "Testing proxy connection..."
            if ! test_proxy "$proxy_value"; then
                log_error "Proxy unreachable"
                return 1
            fi
            echo "$proxy_value" > "$PROXY_FILE"
            apply_proxy_session "$proxy_value"
            clear_git_proxy
            log_success "Proxy enabled"
            ;;
        2)
            disable_proxy
            log_success "Proxy disabled"
            ;;
        3)
            if [[ ! -f "$PROXY_FILE" ]]; then
                log_warn "Proxy is disabled"
                return 0
            fi
            if test_proxy "$(<"$PROXY_FILE")"; then
                log_success "Proxy is reachable"
            else
                log_error "Proxy is unreachable"
            fi
            ;;
        *)
            log_error "Invalid option"
            return 1
            ;;
    esac
}

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

load_proxy

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
    dc ps
    log_info "Checking container health..."
    dc ps --format json | jq -r '.[] | "\(.Name): \(.Health // "N/A")"' 2>/dev/null || dc ps
}

show_logs() {
    local project_dir=$(get_project_dir) || return 1
    cd "$project_dir" || return 1
    read -rp "Enter container name (or 'all'): " container
    if [[ "$container" == "all" ]]; then
        dc logs --tail=100 -f
    else
        dc logs --tail=100 -f "$container"
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

list_ssl_certificates() {
    log_info "Fetching SSL certificates..."
    local certs=$(certbot certificates 2>/dev/null)
    if [[ -z "$certs" ]]; then
        log_warn "No SSL certificates found"
        return 1
    fi
    echo -e "${CYAN}=== SSL Certificates ===${NC}"
    echo ""
    local cert_name=""
    local domains=""
    local expiry=""
    local days_left=""

    certbot certificates 2>/dev/null | while IFS= read -r line; do
        if [[ "$line" =~ Certificate\ Name: ]]; then
            [[ -n "$cert_name" ]] && echo ""
            cert_name=$(echo "$line" | sed 's/Certificate Name://' | xargs)
            echo -e "${BLUE}Certificate Name:${NC} ${YELLOW}$cert_name${NC}"
        elif [[ "$line" =~ Domains: ]]; then
            domains=$(echo "$line" | sed 's/Domains://' | xargs)
            echo -e "${BLUE}Domains:${NC} ${GREEN}$domains${NC}"
        elif [[ "$line" =~ Expiry\ Date: ]]; then
            expiry=$(echo "$line" | sed 's/Expiry Date://' | xargs)
            echo -e "${BLUE}Expiry Date:${NC} ${YELLOW}$expiry${NC}"
            if [[ "$expiry" =~ \(VALID:\ ([0-9]+)\ days\) ]]; then
                days_left="${BASH_REMATCH[1]}"
                if [[ -n "$days_left" ]]; then
                    if [[ $days_left -lt 30 ]]; then
                        echo -e "${RED}  ⚠ Warning: Certificate expires in $days_left days!${NC}"
                    elif [[ $days_left -lt 60 ]]; then
                        echo -e "${YELLOW}  ⚠ Certificate expires in $days_left days${NC}"
                    else
                        echo -e "${GREEN}  ✓ Certificate valid for $days_left more days${NC}"
                    fi
                fi
            fi
        elif [[ "$line" =~ Certificate\ Path: ]]; then
            local cert_path=$(echo "$line" | sed 's/Certificate Path://' | xargs)
            echo -e "${CYAN}Certificate Path:${NC} $cert_path"
        elif [[ "$line" =~ Private\ Key\ Path: ]]; then
            local key_path=$(echo "$line" | sed 's/Private Key Path://' | xargs)
            echo -e "${CYAN}Private Key Path:${NC} $key_path"
        elif [[ "$line" =~ ^-+$ ]]; then
            echo ""
        fi
    done
    echo ""
    log_success "SSL certificates listed"
}

is_khabinja_project() {
    local dir="${1:-$PWD}"
    local project_name
    project_name=$(basename "$dir")

    if [[ "$project_name" == "khabinja" ]]; then
        return 0
    fi

    if [[ -f "$dir/docker-compose.yml" ]] \
        && grep -q 'container_name:[[:space:]]*api' "$dir/docker-compose.yml" \
        && grep -q 'container_name:[[:space:]]*site' "$dir/docker-compose.yml"; then
        return 0
    fi

    return 1
}

resolve_artisan_container() {
    local dir="${1:-$PWD}"
    if [[ -f "$dir/docker-compose.yml" ]] && grep -q 'container_name:[[:space:]]*api' "$dir/docker-compose.yml"; then
        echo "api"
        return 0
    fi
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'api'; then
        echo "api"
        return 0
    fi
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'laravel'; then
        echo "laravel"
        return 0
    fi
    echo "api"
}

stop_nginx_for_certbot() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'nginx'; then
        echo -e "${BLUE}ℹ${NC} Stopping nginx container to free port 80 for certbot..." >&2
        log "INFO: Stopping nginx for certbot"
        docker stop nginx >/dev/null 2>&1 || true
        echo "1"
    else
        echo "0"
    fi
}

start_nginx_after_certbot() {
    local was_running="$1"
    if [[ "$was_running" == "1" ]]; then
        echo -e "${BLUE}ℹ${NC} Starting nginx container again..." >&2
        log "INFO: Starting nginx after certbot"
        docker start nginx >/dev/null 2>&1 || true
    fi
}

issue_ssl() {
    read -rp "Enter domain (e.g. khabinja.com): " domain
    [[ -z "$domain" ]] && { log_error "Domain is required"; return 1; }
    validate_domain "$domain" || { log_error "Invalid domain format"; return 1; }

    local -a cert_args=(-d "$domain" -d "www.$domain")
    if [[ "$domain" == "khabinja.com" ]] || is_khabinja_project "$(get_project_dir 2>/dev/null || echo "")"; then
        cert_args=(-d "$domain" -d "www.$domain" -d "api.$domain" -d "panel.$domain" -d "pma.$domain")
        log_info "Khabinja multi-domain SSL: ${cert_args[*]}"
        echo -e "${YELLOW}Ensure DNS A records for apex, www, api, panel, pma point to this server.${NC}"
    else
        read -rp "Also include api/panel/pma subdomains? (y/N): " multi
        if [[ "$multi" == "y" || "$multi" == "Y" ]]; then
            cert_args=(-d "$domain" -d "www.$domain" -d "api.$domain" -d "panel.$domain" -d "pma.$domain")
        fi
    fi

    local nginx_was_running
    nginx_was_running=$(stop_nginx_for_certbot)

    log_info "Issuing SSL for: ${cert_args[*]}"
    if certbot certonly --standalone "${cert_args[@]}" --agree-tos --email "$EMAIL" --non-interactive; then
        log_success "SSL certificate issued"
        start_nginx_after_certbot "$nginx_was_running"
        return 0
    fi

    log_error "SSL issuance failed"
    start_nginx_after_certbot "$nginx_was_running"
    return 1
}

dc() {
    local compose_file=""
    local env_file=""

    if [[ -f "$PWD/docker-compose.yml" ]]; then
        compose_file="$PWD/docker-compose.yml"
    elif [[ -f "$PWD/prod.docker-compose.yml" ]]; then
        compose_file="$PWD/prod.docker-compose.yml"
    elif [[ -f "$PWD/modules/Primary/Docker/prod.docker-compose.yml" ]]; then
        compose_file="$PWD/modules/Primary/Docker/prod.docker-compose.yml"
    else
        log_error "No compose file found (docker-compose.yml, prod.docker-compose.yml, or modules/Primary/Docker/prod.docker-compose.yml)"
        return 1
    fi

    if [[ -f "$PWD/.env" ]]; then
        env_file="$PWD/.env"
    elif [[ -f "$PWD/api/.env" ]]; then
        env_file="$PWD/api/.env"
    elif [[ -f "$PWD/laravel/.env" ]]; then
        env_file="$PWD/laravel/.env"
    fi

    if [[ -n "$env_file" ]]; then
        docker compose --env-file "$env_file" -f "$compose_file" "$@"
    else
        docker compose -f "$compose_file" "$@"
    fi
}

prepare_khabinja_project() {
    local project_dir="$1"
    cd "$project_dir" || return 1

    if [[ ! -f "$project_dir/api/.env" ]]; then
        log_warn "api/.env is missing. Copy it from the old server before going live."
        if [[ -f "$project_dir/api/.env.example" ]]; then
            read -rp "Copy api/.env.example to api/.env now? (y/N): " copy_env
            if [[ "$copy_env" == "y" || "$copy_env" == "Y" ]]; then
                cp "$project_dir/api/.env.example" "$project_dir/api/.env"
                log_success "Created api/.env from example — edit secrets before production use"
            fi
        fi
    else
        log_success "api/.env found"
    fi

    if [[ ! -f "$project_dir/nginx/auth/.htpasswd" ]]; then
        log_warn "nginx/auth/.htpasswd missing (phpMyAdmin Basic Auth)."
        if [[ -x "$project_dir/scripts/create-pma-auth.sh" ]]; then
            read -rp "Create PMA auth now with scripts/create-pma-auth.sh? (y/N): " create_auth
            if [[ "$create_auth" == "y" || "$create_auth" == "Y" ]]; then
                if command -v htpasswd >/dev/null 2>&1; then
                    bash "$project_dir/scripts/create-pma-auth.sh" || log_warn "PMA auth creation failed"
                else
                    log_warn "htpasswd not found. Install apache2-utils then rerun scripts/create-pma-auth.sh"
                fi
            fi
        fi
    else
        log_success "PMA auth file found"
    fi

    if [[ ! -f "$project_dir/site/nitro.json" && ! -f "$project_dir/site/server/index.mjs" ]]; then
        log_warn "site/ build output missing. Push a built site/ from local, or use menu: Build Frontend."
    fi

    echo -e "${CYAN}DNS checklist:${NC} khabinja.com, www, api, panel, pma → this server IP"
    echo -e "${CYAN}SSL:${NC} run menu option 3 for multi-domain certificate if not issued yet"
}

ensure_khabinja_site_build() {
    local project_dir="$1"
    if [[ -f "$project_dir/site/nitro.json" || -f "$project_dir/site/server/index.mjs" ]]; then
        return 0
    fi
    log_error "site/ Nitro build not found (need site/nitro.json or site/server/index.mjs)."
    log_error "On local: npm run build in unpacksite/, rsync to site/, git push — then Update again."
    log_error "Or use menu option 19) Build Frontend on this server."
    return 1
}

install_project() {
    read -rp "Enter project name (GitHub repo): " project
    [[ -z "$project" ]] && { log_error "Project name is required"; return 1; }
    validate_project "$project" || { log_error "Invalid project name"; return 1; }
    local project_dir="$HOME/$project"
    [[ -d "$project_dir" ]] && { log_error "Project already exists at $project_dir"; return 1; }
    log_info "Cloning project: $project"
    git_cmd clone "https://github.com/$GITHUB_USER/$project.git" "$project_dir" || { log_error "Clone failed"; return 1; }
    cd "$project_dir" || return 1
    echo "$project" > "$PROJECT_FILE"

    if is_khabinja_project "$project_dir"; then
        prepare_khabinja_project "$project_dir"
        ensure_khabinja_site_build "$project_dir" || log_warn "Continuing without site build — site container may fail until site/ is present"
    fi

    log_info "Building and starting containers..."
    dc up -d --build --remove-orphans && log_success "Project installed successfully" || { log_error "Installation failed"; return 1; }
}

update_project() {
    local project
    project=$(get_project) || { log_error "No project found. Install project first."; return 1; }
    local project_dir="$HOME/$project"
    [[ -d "$project_dir" ]] || { log_error "Project directory not found"; return 1; }
    read -rp "Create backup before update? (y/N): " backup_confirm
    if [[ "$backup_confirm" == "y" || "$backup_confirm" == "Y" ]]; then
        backup_project || log_warn "Backup failed, continuing anyway..."
    fi
    cd "$project_dir" || return 1
    log_info "Updating project: $project"
    git_cmd pull || { log_error "Git pull failed"; return 1; }

    if is_khabinja_project "$project_dir"; then
        ensure_khabinja_site_build "$project_dir" || return 1
    fi

    log_info "Rebuilding containers..."
    dc up -d --build --remove-orphans && log_success "Project updated successfully" || { log_error "Update failed"; return 1; }
}

import_khabinja_sql() {
    local project_dir="$1"
    local sql_file="${2:-$project_dir/database/database.sql}"
    [[ -f "$sql_file" ]] || { log_error "SQL file not found: $sql_file"; return 1; }

    local db_user="ferio"
    local db_pass="fOQY41A6KWF"
    local db_name="khabinja_db"
    if [[ -f "$project_dir/docker-compose.yml" ]]; then
        db_user=$(grep -E '^\s*MYSQL_USER:' "$project_dir/docker-compose.yml" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "$db_user")
        db_pass=$(grep -E '^\s*MYSQL_PASSWORD:' "$project_dir/docker-compose.yml" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "$db_pass")
        db_name=$(grep -E '^\s*MYSQL_DATABASE:' "$project_dir/docker-compose.yml" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "$db_name")
    fi

    if ! docker ps --format '{{.Names}}' | grep -qx 'mysql'; then
        log_error "mysql container is not running"
        return 1
    fi

    log_info "Importing $sql_file into $db_name..."
    docker exec -i mysql mysql -u"$db_user" -p"$db_pass" "$db_name" < "$sql_file" \
        && log_success "Database import completed" \
        || { log_error "Database import failed"; return 1; }
}

update_db() {
    local project_dir
    project_dir=$(get_project_dir) || { log_error "No project found"; return 1; }
    cd "$project_dir" || return 1

    local artisan_ctr
    artisan_ctr=$(resolve_artisan_container "$project_dir")

    echo -e "${BLUE}Database options:${NC}"
    echo "  1) Import SQL dump (recommended for khabinja)"
    echo "  2) Artisan migrate --force (non-destructive)"
    echo "  3) Fresh seed / migrateFreshAllSeed (DESTRUCTIVE)"
    echo "  0) Cancel"
    echo ""
    read -rp "Select option: " db_choice
    db_choice=$(persian_to_english "$db_choice")

    case $db_choice in
        1)
            read -rp "SQL path [$project_dir/database/database.sql]: " sql_path
            sql_path=${sql_path:-$project_dir/database/database.sql}
            read -rp "This may overwrite data. Continue? (y/N): " confirm
            [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 0
            import_khabinja_sql "$project_dir" "$sql_path"
            ;;
        2)
            log_info "Running migrate --force on container: $artisan_ctr"
            dc exec -T "$artisan_ctr" php artisan migrate --force \
                && log_success "Migrations applied" \
                || { log_error "Migrate failed"; return 1; }
            ;;
        3)
            echo -e "${RED}This will wipe the database.${NC}"
            read -rp "Type RESET to confirm: " confirm
            [[ "$confirm" != "RESET" ]] && { log_info "Cancelled"; return 0; }
            if dc exec -T "$artisan_ctr" php artisan list 2>/dev/null | grep -q migrateFreshAllSeed; then
                dc exec -T "$artisan_ctr" php artisan migrateFreshAllSeed \
                    && log_success "Database reset with migrateFreshAllSeed" \
                    || { log_error "Fresh seed failed"; return 1; }
            else
                dc exec -T "$artisan_ctr" php artisan migrate:fresh --seed --force \
                    && log_success "Database reset with migrate:fresh --seed" \
                    || { log_error "Fresh seed failed"; return 1; }
            fi
            ;;
        0) return 0 ;;
        *) log_error "Invalid option"; return 1 ;;
    esac
}

build_frontend() {
    local project_dir
    project_dir=$(get_project_dir) || { log_error "No project found"; return 1; }
    cd "$project_dir" || return 1

    if [[ ! -d "$project_dir/unpacksite" ]]; then
        log_error "unpacksite/ not found"
        return 1
    fi

    log_info "Building Nuxt (unpacksite) with node:22 container..."
    docker run --rm \
        -v "$project_dir/unpacksite:/app" \
        -w /app \
        node:22-alpine \
        sh -c "npm ci && npm run build" \
        || { log_error "Frontend build failed"; return 1; }

    log_info "Syncing .output → site/ ..."
    mkdir -p "$project_dir/site"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete --exclude Dockerfile "$project_dir/unpacksite/.output/" "$project_dir/site/"
    else
        find "$project_dir/site" -mindepth 1 ! -name Dockerfile -exec rm -rf {} + 2>/dev/null || true
        cp -a "$project_dir/unpacksite/.output/." "$project_dir/site/"
    fi

    log_success "Frontend built into site/"
    read -rp "Rebuild site container now? (Y/n): " rebuild
    rebuild=${rebuild:-Y}
    if [[ "$rebuild" == "y" || "$rebuild" == "Y" ]]; then
        dc up -d --build site && log_success "site container rebuilt"
    fi
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

persian_to_english() {
    echo "$1" | sed 'y/۰۱۲۳۴۵۶۷۸۹/0123456789/'
}

show_menu() {
    clear
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                    ${YELLOW}XENZ TOOL MENU${NC}                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}GitHub & SSL:${NC}"
    echo "  1) GitHub Auth Login"
    echo "  2) Renew SSL (Certbot)"
    echo "  3) Issue SSL for Domain"
    echo "  4) List SSL Certificates"
    echo ""
    echo -e "${BLUE}Project Management:${NC}"
    echo "  5) Install Project"
    echo "  6) Update Project"
    echo "  7) Backup Project"
    echo "  8) Restore Backup"
    echo "  9) List Backups"
    echo " 10) Delete All Backups"
    echo ""
    echo -e "${BLUE}Database:${NC}"
    echo " 11) Database (Import SQL / Migrate / Fresh)"
    echo ""
    echo -e "${BLUE}Monitoring:${NC}"
    echo " 12) Health Check"
    echo " 13) View Logs"
    echo " 14) System Stats"
    echo ""
    echo -e "${BLUE}Docker:${NC}"
    echo " 15) Docker Info"
    echo " 16) View Logs"
    echo " 17) Cleanup (Remove unused images/volumes)"
    echo " 18) Proxy Settings"
    echo " 19) Build Frontend (Nuxt → site)"
    echo ""
    echo -e "${YELLOW} 0) Exit${NC}"
    echo ""
    read -rp "Select option: " choice
    choice=$(persian_to_english "$choice")
    case $choice in
        1) github_auth && pause ;;
        2) renew_ssl && pause ;;
        3) issue_ssl && pause ;;
        4) list_ssl_certificates && pause ;;
        5) install_project && pause ;;
        6) update_project && pause ;;
        7) backup_project && pause ;;
        8) restore_backup && pause ;;
        9) list_backups && pause ;;
        10) delete_all_backups && pause ;;
        11) update_db && pause ;;
        12) health_check && pause ;;
        13) show_logs ;;
        14) show_stats && pause ;;
        15) docker_info && pause ;;
        16) show_logs ;;
        17) cleanup_docker && pause ;;
        18) manage_proxy && pause ;;
        19) build_frontend && pause ;;
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
