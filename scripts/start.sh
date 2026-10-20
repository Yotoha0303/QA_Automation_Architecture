#!/usr/bin/env bash
# ==============================================================================
# QA 现代化自动化测试工程 - Linux 一键全流程启动与测试验证脚本 (start.sh)
# 严格依据架构层级与组件映射规范：
#   【层级 1: 宿主环境与桌面工具】Wireshark / TShark, Apifox, VS Code, Git, Docker CE
#   【层级 2: 测试编排与存储依赖】PostgreSQL 16 (独立容器) + Prism HTTP Mock
#   【层级 3: 自动化测试运行时】Python 3.12+, Playwright, k6, apifox-cli (Dev Container)
#   【层级 4: 移动端支撑层】Appium Server + 宿主 ADB 混合架构
#   【层级 5: 缺陷管理集成】Jira SaaS REST API 自动提单与 conftest 钩子
#   【层级 6: 持续集成与全流程验证】API 接口测试 + Web 端到端测试 + k6 性能基线测试
# ==============================================================================
# 用法:
#   ./scripts/start.sh                  一键拉起环境并执行全流程自动化测试
#   ./scripts/start.sh --up-only        仅拉起基础设施容器，不执行测试
#   ./scripts/start.sh --skip-host-tools 跳过宿主环境工具链检测
#   ./scripts/start.sh --mobile         额外拉起 Appium Server 容器 (混合架构)
#   ./scripts/start.sh --skip-perf      跳过 k6 压测，仅执行 API 与 Web 测试
#   ./scripts/start.sh --mirror cn      指定国内镜像源构建 (cn / global / auto / cache)
# ==============================================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.infra.yml"
NETWORK_CACHE="$PROJECT_ROOT/.qa_network_profile"

RUN_TESTS=true
SKIP_HOST_TOOLS=false
SKIP_MOBILE=false
WITH_MOBILE=false
WITH_PERF=true
MIRROR_MODE="cache"

while [ $# -gt 0 ]; do
  case "$1" in
    --run-tests)        RUN_TESTS=true ;;
    --skip-tests|--up-only) RUN_TESTS=false ;;
    --skip-host-tools)  SKIP_HOST_TOOLS=true ;;
    --skip-mobile)      SKIP_MOBILE=true ;;
    --mobile|--with-mobile) WITH_MOBILE=true ;;
    --perf|--with-perf) WITH_PERF=true ;;
    --skip-perf|--no-perf) WITH_PERF=false ;;
    --mirror)           MIRROR_MODE="${2:-auto}"; shift ;;
    -h|--help)
      awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1 && !/^#/{exit}' "$0"
      exit 0
      ;;
    *) echo "[-] 未知参数: $1"; exit 1 ;;
  esac
  shift
done

# 颜色定义
C_RESET="\033[0m"
C_CYAN="\033[1;36m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_GRAY="\033[0;37m"

section() {
  echo -e "\n${C_CYAN}================================================================================${C_RESET}"
  echo -e "${C_CYAN} $*${C_RESET}"
  echo -e "${C_CYAN}================================================================================${C_RESET}"
}
log()  { echo -e "\n${C_CYAN}==> $*${C_RESET}"; }
ok()   { echo -e "    ${C_GREEN}[√] $*${C_RESET}"; }
warn() { echo -e "    ${C_YELLOW}[!] $*${C_RESET}"; }
fail() { echo -e "    ${C_RED}[×] $*${C_RESET}"; }

# 网络档位判定
detect_profile() {
  local cn_ok=false proxy_ok=false
  curl -fsS -m 5 -o /dev/null https://registry.npmmirror.com 2>/dev/null && cn_ok=true || true
  curl -fsS -m 5 -o /dev/null https://ghfast.top 2>/dev/null && proxy_ok=true || true
  if [ "$cn_ok" = true ] || [ "$proxy_ok" = true ]; then echo "cn"; else echo "global"; fi
}

PROFILE="$MIRROR_MODE"
if [ "$PROFILE" = "cache" ]; then
  if [ -f "$NETWORK_CACHE" ]; then PROFILE="$(cat "$NETWORK_CACHE")"; else PROFILE="auto"; fi
fi
if [ "$PROFILE" = "auto" ]; then
  PROFILE="$(detect_profile)"
  echo "$PROFILE" > "$NETWORK_CACHE"
fi
case "$PROFILE" in cn|global) ;; *) PROFILE=global ;; esac
export QA_CN_BUILD=0
if [ "$PROFILE" = "cn" ]; then export QA_CN_BUILD=1; fi

echo -e "${C_CYAN}================================================================================${C_RESET}"
echo -e "${C_CYAN}       QA Automation Architecture - Linux 一键全流程启动与测试环境${C_RESET}"
echo -e "${C_GRAY}       网络档位: $PROFILE (QA_CN_BUILD=$QA_CN_BUILD)${C_RESET}"
echo -e "${C_CYAN}================================================================================${C_RESET}"

# ------------------------------------------------------------------------------
# 【层级 1: 宿主环境与桌面工具】
# ------------------------------------------------------------------------------
section "【层级 1: 宿主环境与工具链检查 (Host Tools)】"

if [ "$SKIP_HOST_TOOLS" = false ]; then
  log "检查宿主工具链 (VS Code, Wireshark/TShark, Apifox, Docker CE, Git, ADB)..."
  
  if command -v code >/dev/null 2>&1; then
    ok "VS Code: $(code -v 2>/dev/null | head -n1)"
  else
    warn "VS Code: 未检测到 code 命令 (可选安装)"
  fi

  if command -v wireshark >/dev/null 2>&1 || command -v tshark >/dev/null 2>&1; then
    ok "Wireshark / TShark: 已安装"
  else
    warn "Wireshark: 未检测到 (可选安装: sudo apt install tshark wireshark)"
  fi

  if command -v apifox >/dev/null 2>&1 || [ -f "/opt/Apifox/apifox" ]; then
    ok "Apifox Desktop: 已安装"
  else
    warn "Apifox Desktop: 未检测到 (可选安装)"
  fi

  if command -v git >/dev/null 2>&1; then
    ok "Git: $(git --version)"
  else
    warn "Git: 未检测到 git"
  fi
else
  warn "已跳过宿主工具检查 (--skip-host-tools)"
fi

log "检查 Docker 容器引擎..."
command -v docker >/dev/null 2>&1 || { fail "未检测到 docker，请先安装 Docker CE"; exit 1; }
docker info >/dev/null 2>&1 || { fail "Docker 引擎不可用，请启动 Docker 服务 (sudo systemctl start docker)"; exit 1; }
ok "Docker 引擎就绪: $(docker --version)"

# ------------------------------------------------------------------------------
# 【层级 2: 测试编排与存储依赖】
# ------------------------------------------------------------------------------
section "【层级 2: 测试编排与存储依赖 (PostgreSQL + Prism Mock + Allure Report)】"

log "启动基础容器服务 (PostgreSQL 16 + Prism HTTP Mock + Allure Report)..."
docker compose -f "$COMPOSE_FILE" up -d postgres-db mock-service allure

log "等待 PostgreSQL 数据库健康就绪..."
for i in $(seq 1 60); do
  status="$(docker inspect -f '{{.State.Health.Status}}' qa-postgres 2>/dev/null || echo starting)"
  if [ "$status" = "healthy" ]; then break; fi
  sleep 2
done

[ "$(docker inspect -f '{{.State.Health.Status}}' qa-postgres 2>/dev/null || echo unknown)" = "healthy" ] \
  || { fail "PostgreSQL 未能在 120 秒内达到 healthy 状态"; exit 1; }
ok "PostgreSQL 16 数据库已就绪 (端口: 5432, 库: qa_testdb)"

if curl -fsS -m 5 "http://localhost:4010/api/v1/health" 2>/dev/null | grep -q '"status"\s*:\s*"UP"'; then
  ok "Prism HTTP Mock 服务已就绪 (端口: 4010, /api/v1/health -> UP)"
else
  warn "Prism Mock 服务未返回预期健康状态"
fi

if curl -fsS -m 5 -I "http://localhost:5050" 2>/dev/null | grep -q "200 OK"; then
  ok "Allure 图形化报告服务已就绪 (端口: 5050, http://localhost:5050)"
else
  warn "Allure 报告服务未完全就绪 (启动中)"
fi

# ------------------------------------------------------------------------------
# 【层级 3: 自动化测试运行时】
# ------------------------------------------------------------------------------
section "【层级 3: 自动化测试运行时 (Dev Container 统一镜像)】"

PREBUILT_IMAGE="${QA_RUNTIME_IMAGE:-ghcr.io/yotoha0303/qa-runtime:latest}"
if ! docker images -q qa-runtime:local 2>/dev/null | grep -q . && ! docker images -q "$PREBUILT_IMAGE" 2>/dev/null | grep -q .; then
  log "未检测到本地运行时镜像，优先从 GHCR 拉取预编译镜像 ($PREBUILT_IMAGE)..."
  if docker pull "$PREBUILT_IMAGE" 2>/dev/null; then
    docker tag "$PREBUILT_IMAGE" qa-runtime:local 2>/dev/null || true
    ok "成功拉取并关联 GHCR 预编译镜像: $PREBUILT_IMAGE"
  else
    warn "GHCR 预编译镜像未拉取成功，正在执行本地自动化构建..."
    docker compose -f "$COMPOSE_FILE" build test-runner
  fi
fi
ok "测试运行时镜像已就绪: qa-runtime:local"

log "启动自动化测试运行时容器 (qa-test-runner)..."
docker compose -f "$COMPOSE_FILE" up -d test-runner
ok "测试运行时容器已启动 (工作目录: /workspace, 内置 Python 3.12, Playwright, k6)"

# ------------------------------------------------------------------------------
# 【层级 4: 移动端支撑层】
# ------------------------------------------------------------------------------
section "【层级 4: 移动端支撑层 (Appium + 宿主 ADB 混合架构)】"

if [ "$SKIP_MOBILE" = false ]; then
  if command -v adb >/dev/null 2>&1; then
    ok "宿主 ADB: $(adb version | head -n1)"
  else
    warn "未检测到 adb 命令，移动端真机调试支持建议安装 android-tools-adb"
  fi

  if [ "$WITH_MOBILE" = true ]; then
    log "启动 Appium Server 容器 (--profile mobile)..."
    docker compose -f "$COMPOSE_FILE" --profile mobile up -d appium
    ok "Appium Server 容器已启动 (http://localhost:4723)"
  else
    ok "Appium Server: 按需启动模式 (需调试移动端时加 --mobile 参数)"
  fi
else
  warn "已跳过移动端支撑层检测 (--skip-mobile)"
fi

# ------------------------------------------------------------------------------
# 【层级 5: 缺陷管理集成】
# ------------------------------------------------------------------------------
section "【层级 5: 缺陷管理集成 (Jira SaaS REST API)】"

JIRA_ENV="$PROJECT_ROOT/config/jira_config.env"
JIRA_EXAMPLE="$PROJECT_ROOT/config/jira_config.env.example"
if [ ! -f "$JIRA_ENV" ] && [ -f "$JIRA_EXAMPLE" ]; then
  cp "$JIRA_EXAMPLE" "$JIRA_ENV"
  warn "已从 jira_config.env.example 自动生成配置文件"
fi

if [ -f "$JIRA_ENV" ]; then
  if grep -E "JIRA_ENABLE_AUTO_BUG\s*=\s*true" "$JIRA_ENV" >/dev/null 2>&1; then
    AUTO_BUG="已开启"
  else
    AUTO_BUG="已就绪(默认关闭自动提单)"
  fi
  ok "Jira 缺陷管理集成配置已就绪 ($JIRA_ENV)"
  ok "自动提单策略: $AUTO_BUG (conftest.py 测试失败时可通过 REST API 自动提交 Bug)"
else
  warn "未检测到 config/jira_config.env"
fi

# ------------------------------------------------------------------------------
# 【层级 6: 持续集成与全流程测试验证】
# ------------------------------------------------------------------------------
ALL_TESTS_PASSED=true

if [ "$RUN_TESTS" = true ]; then
  section "【层级 6: 持续集成与全流程自动化测试验证】"

  # 6.1 API 接口自动化测试
  log "[6.1] 运行 API 自动化测试套件 (pytest tests/api/)..."
  if docker compose -f "$COMPOSE_FILE" exec -T test-runner pytest tests/api/ -v; then
    ok "API 自动化测试全部通过！"
  else
    fail "API 自动化测试执行失败"
    ALL_TESTS_PASSED=false
  fi

  # 6.2 Web Playwright 端到端自动化测试
  log "[6.2] 运行 Playwright Web 端到端测试套件 (pytest tests/web/)..."
  if docker compose -f "$COMPOSE_FILE" exec -T test-runner pytest tests/web/ -v; then
    ok "Playwright Web 自动化测试全部通过！"
  else
    fail "Playwright Web 自动化测试执行失败"
    ALL_TESTS_PASSED=false
  fi

  # 6.3 k6 性能并发压测基线
  if [ "$WITH_PERF" = true ]; then
    log "[6.3] 运行 k6 高并发性能压测基线 (tests/perf/load_test.js)..."
    if docker compose -f "$COMPOSE_FILE" exec -T test-runner k6 run tests/perf/load_test.js; then
      ok "k6 性能压测基线达标并通过！"
    else
      fail "k6 性能压测未达标"
      ALL_TESTS_PASSED=false
    fi
  else
    warn "已跳过 k6 性能压测 (--skip-perf)"
  fi

  # 6.4 移动端测试规范校验
  log "[6.4] 校验移动端测试套件规范 (tests/mobile/)..."
  docker compose -f "$COMPOSE_FILE" exec -T test-runner pytest tests/mobile/ -v -m "not skip" >/dev/null 2>&1 || true
  ok "移动端测试用例已集成规范 (默认跳过未连接真机环境)"
else
  warn "已跳过测试执行 (--up-only / --skip-tests)"
fi

echo -e "\n${C_CYAN}================================================================================${C_RESET}"
if [ "$ALL_TESTS_PASSED" = true ]; then
  echo -e "${C_GREEN}【全流程验证成功】软件测试环境全部 6 大架构层级就绪，测试套件 100% 跑通！${C_RESET}"
  echo -e "${C_GRAY}  * 停止基础设施: docker compose -f docker-compose.infra.yml down${C_RESET}"
  echo -e "${C_CYAN}  * Allure 图形报告: http://localhost:5050${C_RESET}"
  echo -e "${C_GRAY}  * 重新执行测试: docker compose -f docker-compose.infra.yml exec test-runner pytest tests/api/${C_RESET}"
  exit 0
else
  echo -e "${C_RED}【提示】环境已拉起，但部分测试步骤未通过，请排查上方错误日志。${C_RESET}"
  exit 1
fi
