#!/bin/bash

set -euo pipefail

log_error() {
    echo -e "\n\e[1;31m❌ Error on line $1. Exit code: $2\e[0m\n"
}
trap 'log_error $LINENO $?' ERR

final_summary() {
    echo ""
    echo -e "\e[1;32m✅ Installation completed successfully\e[0m"
    echo ""
    echo -e "\e[1;34mDocker:\e[0m $(docker --version 2>/dev/null || echo 'not found')"
    echo -e "\e[1;34mDocker Compose:\e[0m $(docker compose version 2>/dev/null || echo 'not found')"
    echo -e "\e[1;34mDocker Buildx:\e[0m $(docker buildx version 2>/dev/null || echo 'not found')"
    echo -e "\e[1;34mGitHub CLI:\e[0m $(gh --version 2>/dev/null | head -n1 || echo 'not found')"
    echo -e "\e[1;34mCertbot:\e[0m $(certbot --version 2>/dev/null || echo 'not found')"
    echo -e "\e[1;34mXenz:\e[0m Run \e[1;33mxenz\e[0m to open the tool menu"
    echo ""
}
trap final_summary EXIT

apt update -y
apt install -y ca-certificates curl gnupg lsb-release

# Detect distro (Debian vs Ubuntu)
DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
CODENAME=$(lsb_release -cs)

if ! command -v docker >/dev/null 2>&1; then
    install -m 0755 -d /etc/apt/keyrings
    if [[ "$DISTRO" == "debian" ]]; then
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $CODENAME stable" \
          | tee /etc/apt/sources.list.d/docker.list > /dev/null
    elif [[ "$DISTRO" == "ubuntu" ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $CODENAME stable" \
          | tee /etc/apt/sources.list.d/docker.list > /dev/null
    else
        echo "❌ Unsupported distro: $DISTRO"
        exit 1
    fi

    apt update -y
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

if ! command -v gh >/dev/null 2>&1; then
    apt install -y gh
fi

if ! command -v certbot >/dev/null 2>&1; then
    apt install -y certbot
fi

# Xenz tool installer
sudo tee /usr/local/bin/xenz > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

PROJECT_FILE="$HOME/.xenz-project"

show_menu() {
    echo ""
    echo -e "\e[1;36m=== XENZ TOOL MENU ===\e[0m"
    echo "1) GitHub Auth Login"
    echo "2) Renew SSL (Certbot)"
    echo "3) Issue SSL for Domain (Certbot)"
    echo "4) Install Project"
    echo "5) Update Project"
    echo "6) Update DB"
    echo "7) Docker Info"
    echo "8) Exit"
    echo ""
    read -rp "Select an option: " choice
    case $choice in
        1) gh auth login ;;
        2) certbot renew ;;
        3)
            read -rp "Enter your domain (e.g. example.com): " DOMAIN
            [[ -z "$DOMAIN" ]] && echo "❌ Domain is required" && exit 1
            certbot certonly --standalone -d "$DOMAIN" -d "www.$DOMAIN" --agree-tos --email you@example.com
            ;;
        4)
            read -rp "Enter project name (GitHub repo): " PROJECT
            [[ -z "$PROJECT" ]] && echo "❌ Project name is required" && exit 1
            echo "$PROJECT" > "$PROJECT_FILE"
            git clone "https://github.com/FarshadGhanbari/$PROJECT.git" && cd "$PROJECT"
            docker compose -f prod.docker-compose.yml up -d --build --remove-orphans
            ;;
        5)
            [[ ! -f "$PROJECT_FILE" ]] && echo "❌ No installed project found." && exit 1
            PROJECT=$(cat "$PROJECT_FILE")
            cd "$HOME/$PROJECT"
            git pull
            docker compose -f prod.docker-compose.yml up -d --build --remove-orphans
            ;;
        6) docker exec -it laravel php artisan db:fresh-seed ;;
        7) docker info ;;
        8) echo "Goodbye." && exit 0 ;;
        *) echo "Invalid option." && show_menu ;;
    esac
}

show_menu
EOF

sudo chmod +x /usr/local/bin/xenz