#!/usr/bin/env bash
# ==============================================================================
# Linux 宿主环境一键部署入口 (setup_host_tools_linux.sh)
# 适用系统: Ubuntu 20.04/22.04/24.04, Debian 11/12 等主流 Linux 发行版
# 安装内容:
#   1. VS Code (官方 APT 源)
#   2. Wireshark / TShark (网络抓包)
#   3. Apifox Desktop (官方 Linux deb 安装包)
#   4. Docker CE & Docker Compose (底层容器引擎)
#   5. ADB (Android Debug Bridge 移动端支撑)
# ==============================================================================

set -e

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "[-] 请使用 sudo 执行本脚本: sudo bash $0"
  exit 1
fi

echo "=========================================================="
echo "      正在开始部署 Linux 宿主环境与核心桌面工具          "
echo "=========================================================="

export DEBIAN_FRONTEND=noninteractive

# 1. 基础包与依赖安装
echo "--> 1. 更新包管理器并安装基础工具..."
apt-get update -y
apt-get install -y curl wget gpg apt-transport-https ca-certificates software-properties-common adb unzip

# 2. 安装 Visual Studio Code (官方源)
echo "--> 2. 配置并安装 Visual Studio Code..."
if ! command -v code &> /dev/null; then
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/packages.microsoft.gpg
    echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
    apt-get update -y
    apt-get install -y code
    echo "[√] VS Code 安装完成"
else
    echo "[√] VS Code 已存在，跳过"
fi

# 3. 安装 Wireshark & TShark
echo "--> 3. 安装 Wireshark 抓包工具..."
if ! command -v wireshark &> /dev/null; then
    echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections
    apt-get install -y wireshark tshark
    REAL_USER=${SUDO_USER:-$USER}
    if [ "$REAL_USER" != "root" ]; then
        usermod -aG wireshark "$REAL_USER" || true
    fi
    echo "[√] Wireshark 安装完成"
else
    echo "[√] Wireshark 已存在，跳过"
fi

# 4. 安装 Docker & Docker Compose
echo "--> 4. 安装 Docker CE 与 Docker Compose 插件..."
if ! command -v docker &> /dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    UBUNTU_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    REAL_USER=${SUDO_USER:-$USER}
    if [ "$REAL_USER" != "root" ]; then
        usermod -aG docker "$REAL_USER" || true
    fi
    systemctl enable docker
    systemctl start docker
    echo "[√] Docker & Compose 安装完成"
else
    echo "[√] Docker 已存在，跳过"
fi

# 5. 下载并安装 Apifox Desktop for Linux (官方真实验证链接)
echo "--> 5. 下载并安装 Apifox Desktop..."
if ! command -v apifox &> /dev/null && [ ! -d "/opt/Apifox" ]; then
    TMP_DIR=$(mktemp -d)
    echo "    正在下载 Apifox deb 归档包..."
    wget -c "https://file-assets.apifox.com/download/Apifox-linux-deb-latest.zip" -O "$TMP_DIR/apifox.zip"
    unzip -q "$TMP_DIR/apifox.zip" -d "$TMP_DIR"
    dpkg -i "$TMP_DIR"/*.deb || apt-get install -f -y
    rm -rf "$TMP_DIR"
    echo "[√] Apifox Desktop 安装完成"
else
    echo "[√] Apifox 已存在，跳过"
fi

echo ""
echo "=========================================================="
echo "【完成】Linux 宿主环境与工具链全部安装就绪！"
echo "=========================================================="
echo "使用提示:"
echo "1. 请重新登录当前用户使 docker 和 wireshark 用户组权限生效。"
echo "2. 打开 VS Code 安装插件: Dev Containers (code --install-extension ms-vscode-remote.remote-containers)"
echo "3. 启动测试基础设施: docker compose -f docker-compose.infra.yml up -d"
echo "=========================================================="
