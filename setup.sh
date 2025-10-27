#!/bin/bash

# Xenz server bootstrapper with hardened error reporting and reusable menu helpers.
set -euo pipefail

script_failed=0

log_error() {
    script_failed=1
    echo -e "\n\e[1;31m❌ Error on line $1. Exit code: $2\e[0m\n"
}
trap 'log_error $LINENO $?' ERR

final_summary() {
    echo ""
    if [[ $script_failed -eq 0 ]]; then
        echo -e "\e[1;32m✅ Installation completed successfully\e[0m"
    else
        echo -e "\e[1;31m⚠️  Installation encountered errors. Review the logs above.\e[0m"
    fi
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

INSTALL_ROOT=${XENZ_INSTALL_ROOT:-$HOME/xenz-projects}
PROJECT_FILE="$HOME/.xenz-project"
CERTBOT_EMAIL_FILE="$HOME/.xenz-certbot-email"

apt update -y

apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common

if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update -y
    apt install -y docker-ce docker-ce-cli containerd.io
fi

if ! docker compose version >/dev/null 2>&1; then
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p "$DOCKER_CONFIG/cli-plugins"
    curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
    chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
fi

if ! docker buildx version >/dev/null 2>&1; then
    mkdir -p ~/.docker/cli-plugins
    curl -SL "https://github.com/docker/buildx/releases/latest/download/buildx-$(uname -s)-$(uname -m)" -o ~/.docker/cli-plugins/docker-buildx
    chmod +x ~/.docker/cli-plugins/docker-buildx
fi

if ! command -v gh >/dev/null 2>&1; then
    apt install -y gh
fi

if ! command -v certbot >/dev/null 2>&1; then
    apt install -y certbot
fi

sudo tee /usr/local/bin/xenz > /dev/null <<'XENZ'
#!/bin/bash
set -euo pipefail

INSTALL_ROOT=${XENZ_INSTALL_ROOT:-$HOME/xenz-projects}
PROJECT_FILE="$HOME/.xenz-project"
CERTBOT_EMAIL_FILE="$HOME/.xenz-certbot-email"

ensure_install_dir() {
    mkdir -p "$INSTALL_ROOT"
}

prompt_certbot_email() {
    local email
    if [[ -f "$CERTBOT_EMAIL_FILE" ]]; then
        read -rp "Enter Certbot email [$(cat "$CERTBOT_EMAIL_FILE")]: " email
        email=${email:-$(cat "$CERTBOT_EMAIL_FILE")}
    else
        read -rp "Enter Certbot email: " email
    fi

    if [[ -z "$email" ]]; then
        echo "❌ Certbot email is required"
        exit 1
    fi

    echo "$email" > "$CERTBOT_EMAIL_FILE"
    CERTBOT_EMAIL="$email"
}

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
        1)
            gh auth login
            ;;
        2)
            if [[ ! -f "$CERTBOT_EMAIL_FILE" ]]; then
                echo "ℹ️  Certbot email not set yet."
                prompt_certbot_email
            fi
            certbot renew
            ;;
        3)
            prompt_certbot_email
            read -rp "Enter your domain (e.g. example.com): " DOMAIN
            if [[ -z "$DOMAIN" ]]; then
                echo "❌ Domain is required"
                exit 1
            fi
            certbot certonly --standalone -d "$DOMAIN" -d "www.$DOMAIN" --agree-tos --email "$CERTBOT_EMAIL"
            ;;
        4)
            ensure_install_dir
            read -rp "Enter GitHub repository (owner/name): " REPO_SLUG
            if [[ -z "$REPO_SLUG" ]]; then
                echo "❌ Repository is required"
                exit 1
            fi
            if [[ ! "$REPO_SLUG" =~ ^[^/]+/[^/]+$ ]]; then
                echo "❌ Repository must be in the format owner/name"
                exit 1
            fi
            REPO_NAME=${REPO_SLUG##*/}
            TARGET_DIR="$INSTALL_ROOT/$REPO_NAME"
            if [[ -d "$TARGET_DIR" ]]; then
                echo "❌ $TARGET_DIR already exists. Remove it or choose another repository."
                exit 1
            fi
            git clone "https://github.com/$REPO_SLUG.git" "$TARGET_DIR"
            echo "$TARGET_DIR" > "$PROJECT_FILE"
            cd "$TARGET_DIR"
            docker compose -f prod.docker-compose.yml up -d --build --remove-orphans
            ;;
        5)
            if [[ ! -f "$PROJECT_FILE" ]]; then
                echo "❌ No installed project found. Please run Install Project first."
                exit 1
            fi
            TARGET_DIR=$(cat "$PROJECT_FILE")
            if [[ ! -d "$TARGET_DIR" ]]; then
                echo "❌ Stored project directory $TARGET_DIR is missing."
                exit 1
            fi
            cd "$TARGET_DIR"
            git pull
            docker compose -f prod.docker-compose.yml up -d --build --remove-orphans
            ;;
        6)
            docker exec -it laravel php artisan db:fresh --seed
            ;;
        7)
            docker info
            ;;
        8)
            echo "Goodbye."
            exit 0
            ;;
        *)
            echo "Invalid option."
            show_menu
            ;;
    esac
}

show_menu
XENZ

sudo chmod +x /usr/local/bin/xenz