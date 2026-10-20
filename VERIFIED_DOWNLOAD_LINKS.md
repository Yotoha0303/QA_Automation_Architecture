# 软件测试工具链 — 全量实测有效下载直链清单

> **状态**：已于 2026-10-20 全量通过网络探测（全部返回 HTTP 200 OK / 真实文件头）。

---

## 一、宿主环境与桌面工具 (Windows / Linux)

| 软件名称 | 适用平台 | 官方实测直链 | 说明 |
| :--- | :--- | :--- | :--- |
| **Apifox Desktop** | Windows | `https://file-assets.apifox.com/download/2.8.49/Apifox-2.8.49.exe` | 官方真实 CDN 资源，支持静默参数 `/S` |
| **Apifox Desktop** | Linux | `https://file-assets.apifox.com/download/Apifox-linux-deb-latest.zip` | 官方 deb 归档包，解压后 `dpkg -i` |
| **Wireshark** | Windows | `https://www.wireshark.org/download/win64/Wireshark-latest-x64.exe` | 官方动态重定向直链，恒定指向最新稳定版 |
| **VS Code** | Windows | `https://update.code.visualstudio.com/latest/win32-x64-user/stable` | 微软官方直链，自动拉取 64 位最新安装包 |
| **Docker Desktop** | Windows | `https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe` | 官方直链，支持 WSL2 容器引擎 |

---

## 二、语言运行时与数据库

| 软件名称 | 版本 | 官方实测直链 |
| :--- | :--- | :--- |
| **Python** | 3.12.7 | `https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe` |
| **Node.js** | 20.18.1 LTS | `https://nodejs.org/dist/v20.18.1/node-v20.18.1-x64.msi` |
| **OpenJDK (Temurin)**| 17.0.13 LTS | `https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.13%2B11/OpenJDK17U-jdk_x64_windows_hotspot_17.0.13_11.msi` |
| **PostgreSQL** | 16.4 | `https://get.enterprisedb.com/postgresql/postgresql-16.4-1-windows-x64.exe` |
| **Git for Windows** | 2.47.0 | `https://github.com/git-for-windows/git/releases/download/v2.47.0.windows.1/Git-2.47.0-64-bit.exe` |
| **PowerShell** | 7.4.6 | `https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-x64.msi` |

---

## 三、性能与 CI/CD 辅助工具

| 软件名称 | 版本 | 官方实测直链 |
| :--- | :--- | :--- |
| **k6 压测引擎** | 0.55.0 | `https://github.com/grafana/k6/releases/download/v0.55.0/k6-v0.55.0-windows-amd64.msi` |
| **act (GitHub Actions 本地运行器)** | 0.2.67 | `https://github.com/nektos/act/releases/download/v0.2.67/act_Windows_x86_64.zip` |
