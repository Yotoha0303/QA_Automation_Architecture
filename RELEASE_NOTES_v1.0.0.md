# Release v1.0.0 - QA 现代化自动化测试工程架构基线发布

欢迎使用 **QA Automation Architecture v1.0.0**！这是本项目的首个正式发布版本。

本项目采用**云原生容器化 + 宿主工具混合架构**设计，严格依据 6 大架构层级构建，实现环境隔离、跨平台一键拉起与端到端全流程无头自动化回归。

---

## 🌟 核心功能与架构特性

### 1. 严格对齐 6 大架构层级
- **【层级 1: 宿主工具链】** 支持 Windows / Linux 宿主环境依赖检查与快速就绪（Wireshark, Apifox Desktop, VS Code, Git, Docker Desktop / CE）。
- **【层级 2: 测试编排与存储依赖】** Docker Compose 容器化调度 PostgreSQL 16 独立数据库与 Prism HTTP Mock 服务，内置动态健康检查。
- **【层级 3: 统一自动化测试运行时】** Dev Container 统一镜像 (`qa-runtime:local`)，封装 Python 3.12+、Playwright 多浏览器内核（Chromium, Firefox, WebKit）、k6 压测引擎及 apifox-cli。
- **【层级 4: 移动端支撑层】** 宿主 ADB 5037 跨容器透明桥接 + Appium Server 容器化混合模式。
- **【层级 5: 缺陷管理集成】** 预置 Jira SaaS REST API 自动化提单集成配置与 Pytest 失败用例自触发钩子。
- **【层级 6: 持续集成与全流程跑通】** 一键运行 API 接口自动化、Playwright Web 端到端测试与 k6 高并发压测基线，生成全层级健康评分卡（Scorecard）。

### 2. 双平台一键拉起与执行入口
- **Windows**：双击即可执行的根目录 [`start.bat`](start.bat) 及 [`scripts/start.ps1`](scripts/start.ps1)。
- **Linux / CI**：根目录一键脚本 [`start.sh`](start.sh) 及 [`scripts/start.sh`](scripts/start.sh)。
- 支持国内镜像源（清华源、npmmirror、GitHub 代理）与官方源智能探测与快速切换 (`-Mirror cn|global|auto`)。

### 3. 完备的工程文档体系
- 📘 [`USER_GUIDE.md`](USER_GUIDE.md)：面向测试开发人员的实战操作手册（各容器服务用法、用例编写、FAQ）。
- 🛠️ [`脚本使用手册.md`](脚本使用手册.md)：底层脚本参数、安全复原与实测基线。
- 📋 [`README.md`](README.md)：架构规范、快速开始与手动验收逐项排查清单。

---

## 📄 开源许可证与声明 (License Notice)

- 本项目正式采用 **[Apache License 2.0](LICENSE)** 开源许可证发布。
- 本项目遵循标准 Apache 2.0 规范，包含完整 [`LICENSE`](LICENSE) 与 [`NOTICE`](NOTICE) 文件。
- 许可声明：
  ```text
  Copyright 2026 Yotoha (https://github.com/Yotoha0303/QA_Automation_Architecture)
  Licensed under the Apache License, Version 2.0
  ```
- 允许自由商业使用、二次分发与修改，受 Apache 2.0 免责声明与专利保护条款保护。
