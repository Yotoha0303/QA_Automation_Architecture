# QA 现代化自动化测试工程 - 用户使用说明书 (User Guide)

本项目基于**云原生容器化 + 宿主工具混合架构**设计，旨在解决企业级测试工具链环境冲突、真机调试隔离与 CI/CD 流水线标准化难题。

本文档面向测试工程师、测试开发工程师（SDET）及运维人员，指导您在 Windows 或 Linux 环境下快速拉起测试环境并开展日常测试开发工作。

---

## 目录

- [一、架构层级与组件映射](#一架构层级与组件映射)
- [二、系统前置要求](#二系统前置要求)
- [三、一键启动与全流程回归 (推荐)](#三一键启动与全流程回归-推荐)
  - [1. Windows 快速开始](#1-windows-快速开始)
  - [2. Linux 快速开始](#2-linux-快速开始)
  - [3. 常用控制参数](#3-常用控制参数)
- [四、各个服务与工具的使用方法](#四各个服务与工具的使用方法)
  - [1. 辅助 Mock 服务 (Prism, 端口 4010)](#1-辅助-mock-服务-prism-端口-4010)
  - [2. PostgreSQL 16 数据库 (端口 5432)](#2-postgresql-16-数据库-端口-5432)
  - [3. 自动化测试运行时 (Dev Container / qa-test-runner)](#3-自动化测试运行时-dev-container--qa-test-runner)
  - [4. 移动端混合支撑层 (宿主 ADB + Appium Server)](#4-移动端混合支撑层-宿主-adb--appium-server)
  - [5. Jira 缺陷管理自动提单](#5-jira-缺陷管理自动提单)
- [五、测试用例编写与执行指南](#五测试用例编写与执行指南)
- [六、手动检查与验收 Checklist](#六手动检查与验收-checklist)
- [七、常见问题与排坑指南 (FAQ)](#七常见问题与排坑指南-faq)
- [八、开源协议](#八开源协议)

---

## 一、架构层级与组件映射

| 架构层级 | 工具与组件 | 部署形态 | 对应配置文件 / 目录 | 职责与功能 |
| :--- | :--- | :--- | :--- | :--- |
| **层级 1: 宿主工具** | Wireshark, Apifox, VS Code, Git, Docker | 宿主原生安装 | `scripts/packages.json`<br>`scripts/setup_host_tools_*` | 底层网络抓包、API 调试协同、代码开发与容器引擎支撑 |
| **层级 2: 存储与编排** | PostgreSQL 16, Prism HTTP Mock | Docker Compose 独立容器 | `docker-compose.infra.yml`<br>`mock-schemas/sample_api.yaml` | 测试数据持久化存储、依据 OpenAPI 契约动态模拟后端响应 |
| **层级 3: 测试运行时** | Python 3.12+, Playwright, k6, apifox-cli | Dev Container 统一镜像 (`qa-runtime:local`) | `.devcontainer/Dockerfile`<br>`docker-compose.infra.yml` | 隔离测试依赖（浏览器内核、压测引擎、测试框架全部在容器内） |
| **层级 4: 移动端支撑** | 宿主 ADB + Appium Server | 混合跨主机桥接模式 | `scripts/start_host_adb.cmd`<br>`docker-compose.infra.yml` (profile `mobile`) | 宿主暴露 5037 端口，容器内 Appium 桥接驱动真机或模拟器 |
| **层级 5: 缺陷管理** | Jira SaaS REST API | 官方 REST SDK 集成 | `config/jira_config.env`<br>`conftest.py` | 测试用例失败时自动触发 REST API 提交缺陷单 |
| **层级 6: 持续集成** | GitHub Actions / 本地全流程回归 | 容器化自动化运行 | `.github/workflows/ci.yml`<br>`start.bat` / `start.sh` | 执行 API、Web、k6 性能测试，生成测试评分表 |

---

## 二、系统前置要求

- **操作系统**：Windows 10/11 (64位) 或 Linux (Ubuntu 20.04/22.04/24.04 等)
- **容器引擎**：已安装并启动 Docker (Windows 推荐 Docker Desktop + WSL2 后端；Linux 推荐 Docker CE)
- **网络条件**：能正常访问 GitHub 或国内镜像代理（脚本内置国内清华源、npmmirror、ghfast 代理智能切换）

---

## 三、一键启动与全流程回归 (推荐)

我们在工程根目录提供了跨平台的一键启动入口，全自动按 6 大架构层级完成工具校验、基础设施启动、健康检查与测试用例验证。

### 1. Windows 快速开始

- **双击运行**：在文件资源管理器中直接双击根目录下的 [`start.bat`](start.bat) 即可。
- **终端运行**：
  ```powershell
  # 执行全流程拉起与自动化测试验证
  .\start.bat

  # 或通过原生 PowerShell 调用
  powershell -ExecutionPolicy Bypass -File .\scripts\start.ps1
  ```

### 2. Linux 快速开始

```bash
chmod +x ./start.sh ./scripts/start.sh
./start.sh
```

### 3. 常用控制参数

| Windows 参数 | Linux 参数 | 说明 | 默认值 |
| :--- | :--- | :--- | :--- |
| `-RunTests` | `--run-tests` | 启动后自动运行全套自动化测试验证 | 开启 (`$true`) |
| `-SkipTests` | `--up-only` 或 `--skip-tests` | 仅拉起容器环境，不执行测试套件 | 关闭 (`$false`) |
| `-OpenVsCode` | — | 测试通过后唤起 VS Code 并通过 Dev Containers 协议直接附着 | 关闭 |
| `-WithMobile` | `--mobile` | 额外启动 Appium Server 移动端容器 | 关闭 |
| `-SkipPerf` | `--skip-perf` | 跳过 k6 压测，仅执行 API 与 Web 测试 | 关闭 |
| `-Mirror cn\|global\|auto` | `--mirror cn\|global\|auto` | 强制使用国内镜像源或官方源构建容器 | `cache` (自动缓存) |

---

## 四、各个服务与工具的使用方法

很多刚接触云原生测试架构的同学在 Docker Desktop 中直接点击链接会遇到打不开的问题，这是因为各组件有对应的协议规范：

### 1. 辅助 Mock 服务 (Prism, 端口 4010)

Prism 是一个基于 OpenAPI 契约规范的 Mock 引擎。

- **为什么点 `http://localhost:4010/` 报 404？**
  Mock 服务只匹配在规范文件 (`mock-schemas/sample_api.yaml`) 中明确定义的路由，访问根路径会返回 `Route not resolved`。
- **如何正常访问？**
  - **健康检查接口**：在浏览器或 Postman 中访问：[http://localhost:4010/api/v1/health](http://localhost:4010/api/v1/health)  
    *(返回 `{"status":"UP","timestamp":"..."}`)*
  - **用户信息接口**：在浏览器访问：[http://localhost:4010/api/v1/users/1001](http://localhost:4010/api/v1/users/1001)  
    *(返回模拟的用户信息 JSON)*
- **在 Apifox Desktop 中使用**：
  打开宿主机安装好的 Apifox，将环境前置 URL 配置为 `http://localhost:4010`，即可进行接口协同与用例编排。

---

### 2. PostgreSQL 16 数据库 (端口 5432)

PostgreSQL 是数据库协议服务，不能直接用网页浏览器访问。

- **连接信息**：
  - **主机 (Host)**: `localhost` (容器内互联用 `qa-postgres`)
  - **端口 (Port)**: `5432`
  - **用户名 (User)**: `qa_admin`
  - **密码 (Password)**: `QAPassword123!`
  - **数据库名 (Database)**: `qa_testdb`
- **使用客户端连接**：
  在 Navicat、DBeaver、DataGrip 或 VS Code Database 插件中新建 PostgreSQL 连接，填入上述信息即可查看测试数据表与持久化记录。
- **终端交互查询**：
  ```bash
  docker compose -f docker-compose.infra.yml exec postgres-db psql -U qa_admin -d qa_testdb -c "SELECT 1;"
  ```

---

### 3. 自动化测试运行时 (Dev Container / qa-test-runner)

测试运行时容器包含了 Python 3.12+、Playwright 浏览器驱动内核（Chromium/Firefox/WebKit）、k6 压测引擎及 apifox-cli。

#### 模式 A：通过 VS Code 附着开发（推荐）
1. 运行 `.\start.bat -OpenVsCode`。
2. 或在 VS Code 中按 `F1`，选择 **`Dev Containers: Reopen in Container`**。
3. 进入容器后，代码编辑即时生效，可直接在 VS Code 内部终端执行 `pytest` 或 `k6`。

#### 模式 B：宿主机命令行直接下发命令
宿主机上无需配置任何 Python 或 Playwright 环境，直接下发命令给容器执行：
```bash
# 1. 运行 API 自动化测试
docker compose -f docker-compose.infra.yml exec test-runner pytest tests/api/ -v

# 2. 运行 Web Playwright 自动化测试
docker compose -f docker-compose.infra.yml exec test-runner pytest tests/web/ -v

# 3. 运行 k6 高并发性能压测
docker compose -f docker-compose.infra.yml exec test-runner k6 run tests/perf/load_test.js

# 4. 进入容器 Bash 交互界面
docker compose -f docker-compose.infra.yml exec test-runner bash
```

---

### 4. Allure 测试可视化报告服务 (端口 5050)

项目中已集成基于 Docker 的 Allure Report 可视化服务 (`qa-allure`)，并通过 `conftest.py` 全自动注入 `--alluredir=allure-results`。

- **工作机制**：当您运行任何 pytest 测试用例（API、Web、移动端）时，测试结果数据均会自动输出至 `./allure-results`。Allure 容器会实时监听该目录，自动渲染交互式图形化报告。
- **直观查看报告**：直接在浏览器中打开：👉 [http://localhost:5050](http://localhost:5050)
- **报告特性**：
  * **总体大屏 (Overview)**：通过率仪表盘、耗时曲线、测试用例统计。
  * **行为驱动层级 (Behaviors / Suites)**：按照用例套件与功能模块清晰展示测试层级。
  * **详细错误堆栈与步骤 (Timeline / Retries)**：直观查看每个失败用例的详细堆栈与断言失败现场。

---

### 5. 移动端混合支撑层 (宿主 ADB + Appium Server)

本项目移动端采用混合架构：
- 宿主机运行真机连接或本地 Android 模拟器，宿主 ADB 监听 `0.0.0.0:5037`。
- Appium Server 容器通过 `host.docker.internal:5037` 穿透连接宿主设备。
- 启动 Appium 容器：
  ```bash
  docker compose -f docker-compose.infra.yml --profile mobile up -d appium
  ```
- Appium 访问地址：`http://localhost:4723`（容器内为 `http://appium:4723`）。

---

### 5. Jira 缺陷管理自动提单

- 配置文件位于 `config/jira_config.env`（从 `config/jira_config.env.example` 复制生成）。
- 配置项说明：
  ```env
  JIRA_ENABLE_AUTO_BUG=false    # 是否开启用例失败自动创建 Bug (默认 false 防止测试干扰生产)
  JIRA_SERVER_URL=https://your-domain.atlassian.net/
  JIRA_USER_EMAIL=qa@yourcompany.com
  JIRA_API_TOKEN=your_token_here
  JIRA_PROJECT_KEY=QA
  ```
- 工作机制：测试框架在 `conftest.py` 中注册了 Pytest 测试结果钩子。当测试用例执行失败且开关开启时，将自动调用 Jira REST API 生成包含详细报错堆栈的 Bug 单。

---

## 五、测试用例编写与执行指南

### 1. API 测试 (`tests/api/`)
使用 `pytest` + `requests` + `psycopg2`，已预配置 Mock 服务直连与数据库直连断言：
```python
def test_mock_get_user_info():
    url = "http://qa-mock-service:4010/api/v1/users/1001"
    resp = requests.get(url)
    assert resp.status_code == 200
    assert resp.json().get("username") == "test_engineer"
```

### 2. Web 自动化测试 (`tests/web/`)
基于 Playwright 原生夹具，支持多浏览器无头并发执行：
```python
def test_playwright_web_navigation(page: Page):
    page.goto("https://playwright.dev/")
    expect(page).to_have_title(re.compile(r"Playwright"))
```

### 3. 性能基线测试 (`tests/perf/load_test.js`)
基于 k6 引擎定义高并发阶段阶梯与 SLA 响应时间阈值：
```javascript
export const options = {
  stages: [
    { duration: '5s', target: 10 },
    { duration: '10s', target: 10 },
    { duration: '2s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% 请求必须在 500ms 内完成
  },
};
```

---

## 六、手动检查与验收 Checklist

执行以下命令快速完成环境可用性自验：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\3_verify_operational.ps1
```

正常输出评分卡样例：
```text
测试组件                    业务分类       测试结果   详细运行信息
----                    ----       ----   ------
1. Wireshark            抓包与底层协议    √ 正常可用 二进制已就绪: C:\Program Files\Wireshark\Wireshark.exe
2. Apifox Desktop       API 协同与调试  √ 正常可用 客户端就绪: C:\Users\...\Apifox.exe
3. Visual Studio Code   主开发与调试 IDE √ 正常可用 VS Code 1.132.0
4. Git / Shell (Bash)   命令行终端支撑    √ 正常可用 git version 2.55.0.windows.5
5. PostgreSQL 数据库       数据持久化存储    √ 正常可用 容器 qa-postgres: Up (healthy)
6. k6 性能压测              高并发压测      √ 正常可用 k6 v2.3.0 (容器 qa-runtime:local)
7. Playwright (Web 自动化) 端到端自动化     √ 正常可用 容器 Chromium 拉起并访问网页成功
```

---

## 七、常见问题与排坑指南 (FAQ)

### Q1: 提示 `Docker 引擎不可用，请手动启动 Docker Desktop 后重试`
- **原因**：宿主机的 Docker Desktop 未启动或 WSL2 后端异常。
- **解决**：打开 Docker Desktop 客户端，等待左下角引擎状态变为绿色 `Engine running` 即可。

### Q2: 为什么宿主机直接运行 `pytest tests/api/` 会报 ModuleNotFoundError？
- **原因**：根据架构矩阵规范，Python 测试运行时所有第三方库（Playwright、requests、psycopg2 等）均严格封装在 `qa-runtime:local` 容器中，宿主机不污染全局 Python 环境。
- **解决**：在容器内执行（使用 `.\start.bat`、VS Code Dev Container 或 `docker compose exec test-runner pytest ...`）。

### Q3: 为什么构建容器时下载依赖很慢？
- **解决**：在启动时指定国内镜像源参数：`.\start.bat -Mirror cn` 或 `./start.sh --mirror cn`。脚本会自动切换 Ubuntu 清华源、npmmirror、清华 pip 源与 GitHub 代理。

### Q4: 如何完全停止并重置环境？
- **解决**：执行以下命令停止全部容器并释放端口：
  ```bash
  docker compose -f docker-compose.infra.yml down
  ```

---

## 八、开源协议

本项目遵循 **[Apache License 2.0](LICENSE)** 开源许可证。详见工程根目录下的 `LICENSE` 文件。
