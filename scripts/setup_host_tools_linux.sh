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
    UBUNTU_CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
    DOCKER_OK=false

    # 首选: Docker 官方源 (download.docker.com)
    # apt-get 本身没有可靠的超时控制，官方源在部分网络下只有 ~20KB/s 而不会报错，
    # 会导致脚本挂起数小时。先测速，太慢直接跳过；再用 timeout 兜底。
    DOCKER_APT_TIMEOUT=${DOCKER_APT_TIMEOUT:-900}
    DOCKER_MIN_SPEED=${DOCKER_MIN_SPEED:-200000}   # 字节/秒，低于此值视为不可用
    docker_repo_speed=0
    if command -v curl &> /dev/null; then
        docker_repo_speed=$(curl -s -o /dev/null -m 10 -r 0-2000000 \
            -w '%{speed_download}' "https://download.docker.com/linux/ubuntu/dists/$UBUNTU_CODENAME/Release" 2>/dev/null || echo 0)
        docker_repo_speed=${docker_repo_speed%.*}
    fi

    if [ "${docker_repo_speed:-0}" -lt "$DOCKER_MIN_SPEED" ]; then
        echo "[!] Docker 官方源速度过低 (${docker_repo_speed} B/s < ${DOCKER_MIN_SPEED} B/s)，跳过官方源"
    elif curl -fsSL --connect-timeout 10 --max-time 60 https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc 2>/dev/null; then
        chmod a+r /etc/apt/keyrings/docker.asc
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        if timeout "$DOCKER_APT_TIMEOUT" apt-get update -y >/dev/null 2>&1 \
           && timeout "$DOCKER_APT_TIMEOUT" apt-get install -y -o Dpkg::Use-Pty=0 docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
            DOCKER_OK=true
        else
            echo "[!] Docker 官方源安装超时 (>${DOCKER_APT_TIMEOUT}s) 或失败"
        fi
    fi

    # 回退: 发行版官方仓库 (速度慢或官方源不可用时的兜底)
    if [ "$DOCKER_OK" != true ]; then
        echo "[!] 回退到发行版仓库 (docker.io + docker-compose-v2)..."
        rm -f /etc/apt/sources.list.d/docker.list
        apt-get update -y
        if apt-get install -y docker.io docker-compose-v2; then
            DOCKER_OK=true
        else
            apt-get install -y docker.io docker-compose || true
        fi
    fi

    if command -v docker &> /dev/null; then
        DOCKER_OK=true
        REAL_USER=${SUDO_USER:-$USER}
        if [ "$REAL_USER" != "root" ]; then
            usermod -aG docker "$REAL_USER" || true
        fi
        systemctl enable docker 2>/dev/null || true
        systemctl start docker 2>/dev/null || true
        echo "[√] Docker & Compose 安装完成: $(docker --version)"
    else
        echo "[×] Docker 安装失败，请手动安装后重试"
        exit 1
    fi
else
    echo "[√] Docker 已存在，跳过"
    # Snap 版 Docker 不支持项目目录的 bind mount，给出明确告警
    if docker info 2>/dev/null | grep -qi "snap"; then
        echo "[!] 检测到 Snap 版 Docker：它无法挂载项目目录 (仅支持 \$HOME 下路径)。"
        echo "    建议卸载后使用 Docker CE: sudo snap remove docker && 重新运行本脚本"
    fi
fi

# 5. 下载并安装 Apifox Desktop for Linux (官方真实验证链接)
echo "--> 5. 下载并安装 Apifox Desktop..."
if ! command -v apifox &> /dev/null && [ ! -d "/opt/Apifox" ]; then
    TMP_DIR=$(mktemp -d)
    echo "    正在下载 Apifox deb 归档包..."
    if wget -c "https://file-assets.apifox.com/download/Apifox-linux-deb-latest.zip" -O "$TMP_DIR/apifox.zip" \
       && unzip -q "$TMP_DIR/apifox.zip" -d "$TMP_DIR"; then
        # dpkg 失败时先补齐依赖，再重试安装本 deb (仅 apt-get install -f 不会重装它)
        if ! dpkg -i "$TMP_DIR"/*.deb; then
            apt-get install -f -y
            dpkg -i "$TMP_DIR"/*.deb || true
        fi
    fi
    rm -rf "$TMP_DIR"
    if command -v apifox &> /dev/null || [ -d "/opt/Apifox" ]; then
        echo "[√] Apifox Desktop 安装完成"
    else
        echo "[!] Apifox Desktop 安装失败（不影响自动化测试，可稍后手动安装）"
    fi
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
