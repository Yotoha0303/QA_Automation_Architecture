# ==============================================================================
# 自动化测试运行时统一镜像 (Dev Container)
# 包含: Python 3.12+, Playwright (全浏览器内核), k6 压测引擎, apifox-cli, Appium 客户端
#
# 构建参数:
#   QA_CN_BUILD=1  使用国内镜像源（Node npmmirror / k6 GitHub 代理 / pip 清华 / npm npmmirror）
#   QA_CN_BUILD=0  使用官方源（默认）
#   由 scripts/start.ps1 / start.sh 根据 -Mirror 档位自动注入，也可手动:
#     docker compose build --build-arg QA_CN_BUILD=1 test-runner
# ==============================================================================
FROM mcr.microsoft.com/playwright/python:v1.48.0-noble

ARG QA_CN_BUILD=0
ARG GITHUB_PROXY=https://ghfast.top
ARG K6_VERSION=v2.3.0
ARG NODE_VERSION=v20.20.2

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# 1. 国内构建时切换 Ubuntu 软件源（noble 使用 deb822 格式）
RUN if [ "$QA_CN_BUILD" = "1" ]; then \
        sed -i 's@//.*archive.ubuntu.com@//mirrors.tuna.tsinghua.edu.cn@g; s@//security.ubuntu.com@//mirrors.tuna.tsinghua.edu.cn@g' \
            /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true; \
    fi

# 2. 基础工具
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        gnupg \
        ca-certificates \
        git \
        jq \
        xz-utils \
        adb \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 3. Node.js 20.x
#    国内: npmmirror 二进制直下（不依赖 nodesource 源）
#    官方: NodeSource APT 源
RUN if [ "$QA_CN_BUILD" = "1" ]; then \
        curl -fsSL "https://cdn.npmmirror.com/binaries/node/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz" -o /tmp/node.tar.xz \
        && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
        && rm -f /tmp/node.tar.xz; \
    else \
        mkdir -p /etc/apt/keyrings \
        && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
        && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
        && apt-get update && apt-get install -y nodejs \
        && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# 4. k6 性能测试引擎
#    国内: 通过 GitHub 代理下载官方二进制
#    官方: 官方 APT 源
RUN if [ "$QA_CN_BUILD" = "1" ]; then \
        curl -fsSL "${GITHUB_PROXY}/https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-linux-amd64.tar.gz" -o /tmp/k6.tar.gz \
        && tar -xzf /tmp/k6.tar.gz -C /tmp \
        && install -m 0755 /tmp/k6-${K6_VERSION}-linux-amd64/k6 /usr/local/bin/k6 \
        && rm -rf /tmp/k6.tar.gz /tmp/k6-${K6_VERSION}-linux-amd64; \
    else \
        gpg -k \
        && gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69 \
        && echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | tee /etc/apt/sources.list.d/k6.list \
        && apt-get update && apt-get install -y k6 \
        && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# 5. 全局安装 apifox-cli（npm 源随 QA_CN_BUILD 切换）
RUN if [ "$QA_CN_BUILD" = "1" ]; then \
        npm install -g apifox-cli --registry=https://registry.npmmirror.com; \
    else \
        npm install -g apifox-cli; \
    fi

# 6. Python 测试套件（pip 源随 QA_CN_BUILD 切换）
COPY requirements.txt /tmp/requirements.txt
RUN if [ "$QA_CN_BUILD" = "1" ]; then \
        pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple; \
    fi \
    && pip install --no-cache-dir -r /tmp/requirements.txt

# 7. 预装 Playwright 浏览器内核 (Chromium, Firefox, WebKit)
#    基础镜像已内置，此处确保与包版本匹配；国内构建可另行设置 PLAYWRIGHT_DOWNLOAD_HOST
RUN playwright install --with-deps

WORKDIR /workspace
CMD ["/bin/bash"]
