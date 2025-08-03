#!/bin/bash

set -euo pipefail

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
    mkdir -p $DOCKER_CONFIG/cli-plugins
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o $DOCKER_CONFIG/cli-plugins/docker-compose
    chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
fi

if ! docker buildx version >/dev/null 2>&1; then
    mkdir -p ~/.docker/cli-plugins
    curl -SL https://github.com/docker/buildx/releases/latest/download/buildx-$(uname -s)-$(uname -m) -o ~/.docker/cli-plugins/docker-buildx
    chmod +x ~/.docker/cli-plugins/docker-buildx
fi

if ! command -v gh >/dev/null 2>&1; then
    apt install -y gh
fi

if ! command -v certbot >/dev/null 2>&1; then
    apt install -y certbot
fi

# نصب xenz در مسیر قابل دسترسی
cat << 'EOF' > /usr/local/bin/xenz
#!/bin/bash

set -euo pipefail

show_menu() {
    echo ""
    echo -e "\e[1;36m======= XENZ TOOL MENU =======\e[0m"
    echo "1) GitHub Auth Login"
    echo "2) Certbot Renew"
    echo "3) Docker Info"
    echo "4) Exit"
    echo ""
    read -rp "انتخاب کن: " choice

    case $choice in
        1) gh auth login ;;
        2) certbot renew ;;
        3) docker info ;;
        4) echo "خروج" && exit 0 ;;
        *) echo "گزینه نامعتبر!" && show_menu ;;
    esac
}

show_menu
EOF

chmod +x /usr/local/bin/xenz

echo ""
echo -e "\e[1;32m✅ نصب با موفقیت انجام شد\e[0m"
echo ""
echo -e "\e[1;34m👉 Docker:\e[0m $(docker --version)"
echo -e "\e[1;34m👉 Docker Compose:\e[0m $(docker compose version)"
echo -e "\e[1;34m👉 Docker Buildx:\e[0m $(docker buildx version)"
echo -e "\e[1;34m👉 GitHub CLI:\e[0m $(gh --version | head -n1)"
echo -e "\e[1;34m👉 Certbot:\e[0m $(certbot --version)"
echo -e "\e[1;34m👉 Xenz Command:\e[0m تایپ کن \e[1;33mxenz\e[0m برای منوی ابزار"
echo ""