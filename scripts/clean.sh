#!/usr/bin/env bash
# ==============================================================================
# QA 现代化自动化测试工程 - Linux 环境清理与生命周期闭环脚本 (clean.sh)
# 实现测试机环境“随开随用、用完即净”的完整生命周期管理：
#   1. 停止并清理全部 QA 容器与网络
#   2. 清理测试结果与运行缓存 (allure-results, allure-reports, .pytest_cache)
#   3. 释放宿主端口与网络资源
#   4. 可选清理数据卷与测试镜像
# ==============================================================================
# 用法:
#   ./clean.sh              标准清理 (关闭全部容器，清理测试缓存，释放端口)
#   ./clean.sh -v           同时清理 Docker 数据卷 (PostgreSQL 数据库重置)
#   ./clean.sh -a           彻底清理: 容器 + 数据卷 + 本地 qa-runtime 镜像
#   ./clean.sh --keep-results 保留 allure-results 目录中的测试数据
# ==============================================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.infra.yml"

CLEAN_VOLUMES=false
CLEAN_IMAGES=false
KEEP_RESULTS=false

while [ $# -gt 0 ]; do
  case "$1" in
    -v|--volumes)       CLEAN_VOLUMES=true ;;
    -i|--images)        CLEAN_IMAGES=true ;;
    -a|--all)           CLEAN_VOLUMES=true; CLEAN_IMAGES=true ;;
    --keep-results)     KEEP_RESULTS=true ;;
    -h|--help)
      awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1 && !/^#/{exit}' "$0"
      exit 0
      ;;
    *) echo "[-] 未知参数: $1"; exit 1 ;;
  esac
  shift
done

C_RESET="\033[0m"
C_CYAN="\033[1;36m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_GRAY="\033[0;37m"

log()  { echo -e "\n${C_CYAN}==> $*${C_RESET}"; }
ok()   { echo -e "    ${C_GREEN}[√] $*${C_RESET}"; }
warn() { echo -e "    ${C_YELLOW}[!] $*${C_RESET}"; }

echo -e "${C_CYAN}================================================================================${C_RESET}"
echo -e "${C_CYAN}       QA Automation Architecture - Linux 环境清理与生命周期闭环${C_RESET}"
echo -e "${C_GRAY}       (随开随用、用完即净：容器关闭、端口释放、缓存清理)${C_RESET}"
echo -e "${C_CYAN}================================================================================${C_RESET}"

# 1. 停止并清理 Docker 容器
log "停止并清理 Docker 容器与基础设施..."
if command -v docker >/dev/null 2>&1; then
  if [ "$CLEAN_VOLUMES" = true ]; then
    warn "执行 docker compose down -v (包含数据卷清理)..."
    docker compose -f "$COMPOSE_FILE" down -v --remove-orphans || true
  else
    docker compose -f "$COMPOSE_FILE" down --remove-orphans || true
  fi
  ok "所有 QA 容器与专属网桥网络已停止并释放"

  if [ "$CLEAN_IMAGES" = true ]; then
    log "清理本地测试运行时镜像 (qa-runtime:local)..."
    docker rmi qa-runtime:local 2>/dev/null || true
    ok "已清理 qa-runtime:local 本地镜像"
  fi
else
  warn "未检测到 docker 命令，跳过容器清理"
fi

# 2. 停止宿主 ADB Server (若存在)
if command -v adb >/dev/null 2>&1; then
  adb kill-server >/dev/null 2>&1 || true
  ok "已执行 adb kill-server (5037 端口已释放)"
fi

# 3. 清理测试结果与缓存目录
log "清理测试结果与框架运行时缓存..."
rm -rf "$PROJECT_ROOT/.pytest_cache" \
       "$PROJECT_ROOT/test-results" \
       "$PROJECT_ROOT/playwright-report" \
       "$PROJECT_ROOT/blob-report" \
       "$PROJECT_ROOT/.qa_network_profile" || true

if [ "$KEEP_RESULTS" = false ]; then
  rm -rf "$PROJECT_ROOT/allure-results" "$PROJECT_ROOT/allure-reports" || true
  ok "已清理 allure-results 与 allure-reports"
fi

# 递归清理 __pycache__
find "$PROJECT_ROOT" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
ok "已清理 Python __pycache__ 缓存"

echo -e "\n${C_CYAN}================================================================================${C_RESET}"
echo -e "${C_GREEN}【环境清理完成】测试环境已完全复原，端口已释放，达到“用完即净”标准！${C_RESET}"
echo -e "${C_CYAN}  * 下次拉起环境: 直接执行 ./start.sh${C_RESET}"
echo -e "${C_CYAN}================================================================================${C_RESET}"
