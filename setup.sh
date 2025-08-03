#!/bin/bash

set -euo pipefail

# Final summary on exit
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

# Ensure required base packages
apt update -y
apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common

# Docker installation
if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update -y
    apt install -y docker-ce docker-ce-cli containerd.io
fi

# Docker Compose CLI plugin
if ! docker compose version >/dev/null 2>&1; then
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p "$DOCKER_CONFIG/cli-plugins"
    curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
    chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
fi

# Docker Buildx CLI plugin
if ! docker buildx version >/dev/null 2>&1; then
    mkdir -p ~/.docker/cli-plugins
    curl -SL "https://github.com/docker/buildx/releases/latest/download/buildx-$(uname -s)-$(uname -m)" -o ~/.docker/cli-plugins/docker-buildx
    chmod +x ~/.docker/cli-plugins/docker-buildx
fi

# GitHub CLI
if ! command -v gh >/dev/null 2>&1; then
    apt install -y gh
fi

# Certbot
if ! command -v certbot >/dev/null 2>&1; then
    apt install -y certbot
fi

# Install or overwrite 'xenz' command
sudo tee /usr/local/bin/xenz > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

show_menu() {
    echo ""
    echo -e "\e[1;36m=== XENZ TOOL MENU ===\e[0m"
    echo "1) GitHub Auth Login"
    echo "2) Renew SSL (Certbot)"
    echo "3) Docker Info"
    echo "4) Exit"
    echo ""
    read -rp "Select an option: " choice
    case $choice in
        1) gh auth login ;;
        2) certbot renew ;;
        3) docker info ;;
        4) echo "Goodbye." && exit 0 ;;
        *) echo "Invalid option." && show_menu ;;
    esac
}

show_menu
EOF

sudo chmod +x /usr/local/bin/xenz
