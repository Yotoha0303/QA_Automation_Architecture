# 版本变更日志 (Changelog)

本项目遵循 [Semantic Versioning (语义化版本 2.0.0)](https://semver.org/lang/zh-CN/) 规范。

---

## [v1.0.3] - 2026-10-20

### 新增特性 (Features)
- **数据库初始 Schema 与种子数据挂载**：
  - 新增 [`sql/init.sql`](sql/init.sql)，预置 `users`（测试人员与角色）、`test_cases`（测试用例清单）、`test_executions`（执行日志）三张核心表结构与种子数据。
  - 在 [`docker-compose.infra.yml`](docker-compose.infra.yml) 中配置 `./sql:/docker-entrypoint-initdb.d:ro` 只读挂载，容器首次创建时由 PostgreSQL 引擎全自动初始化。
  - 在 [`tests/api/test_api_sample.py`](tests/api/test_api_sample.py) 中新增 `test_postgres_init_schema_and_seed_data` 用例，直连校验数据库初始化后的表结构与预置数据。
- **Web 端 Page Object Model (POM) 最小化封装**：
  - 建立标准 POM 层次结构：页面基类 [`tests/web/pages/base_page.py`](tests/web/pages/base_page.py) 与业务页面对象 [`tests/web/pages/playwright_home_page.py`](tests/web/pages/playwright_home_page.py)。
  - 彻底解耦 UI 元素定位器、用户交互动作与测试断言，新增端到端工作流用例 `test_playwright_web_pom_workflow`。
- **文档体系同步与全球化 SEO 优化**：
  - 更新 [`README.md`](README.md) 与 [`USER_GUIDE.md`](USER_GUIDE.md)，详尽补充 POM 结构设计规范与 PostgreSQL 预置数据查询指导。
  - **避免图表/iframe 关键词不可检索**：在 `README.md` 与 `README_EN.md` 中增设核心数据流与技术选型检索表（Keyword Matrix），使技术栈关键词可被各大搜索引擎爬虫语义索引。
  - **增设双语 README 导航**：新增高规格英文版技术说明书 [`README_EN.md`](README_EN.md)，并在中英文主页顶部提供快速双语切换导航。
  - **Google Image SEO 优化**：新增高清晰度矢量架构图 [`docs/images/architecture_diagram.svg`](docs/images/architecture_diagram.svg)，配置完备且富有上下文语义的 `alt` 与 `title` 图片属性。
  - **高频报错与长尾痛点问答区 (FAQ)**：在 [`USER_GUIDE.md`](USER_GUIDE.md) 中系统梳理涵盖 Docker、端口冲突、权限策略、POM 导入机制、Postgres 卷初始化、跨主机 ADB 桥接、k6 压测并发等 12 项长尾排障指南。

---

## [v1.0.2] - 2026-10-20

### 新增特性 (Features)
- **架构全景与数据流交互图**：
  - 在 [`README.md`](README.md) 与 [`USER_GUIDE.md`](USER_GUIDE.md) 中引入 Mermaid 架构全景图，清晰梳理 6 大架构层级中 Dev Container、Compose 服务、宿主工具链与 Allure 报告服务之间的数据流向。
- **CI/CD 与镜像徽标**：
  - 在 [`README.md`](README.md) 顶部补充 GitHub Actions CI Pipeline 状态、GHCR Docker 镜像标签、Release 发布版本等直观徽标。

---

## [v1.0.1] - 2026-10-20

### 新增特性 (Features)
- **Allure Report 可视化报告服务集成**：
  - 在 [`docker-compose.infra.yml`](docker-compose.infra.yml) 中集成 `allure` 容器服务（基于 `frankescobar/allure-docker-service:latest`，暴露端口 `5050`）。
  - 在 [`conftest.py`](conftest.py) 中注入 Allure 钩子，执行任意 pytest 测试时自动输出结果至 `allure-results`，支持 `http://localhost:5050` 实时渲染交互式大屏。
- **环境清理与生命周期闭环脚本**：
  - 根目录及 `scripts/` 下新增 [`clean.bat`](clean.bat)、[`clean.sh`](clean.sh) 与 [`scripts/clean.ps1`](scripts/clean.ps1)，实现环境“随开随用、用完即净”的生命周期闭环。
  - 支持常用参数：`-v`（重置数据库持久化卷）、`-a`（彻底清理包含本地镜像）。
- **GitHub Actions GHCR 预编译镜像自动发布**：
  - 新增 [`.github/workflows/publish_ghcr.yml`](.github/workflows/publish_ghcr.yml)，自动将 6.5GB 测试运行时镜像构建并推送到 GitHub Container Registry (`ghcr.io/yotoha0303/qa-runtime:latest`)。
  - 启动脚本 `start.bat` / `start.sh` 支持优先从 GHCR 极速拉取镜像，新开发者免除 15~20 分钟本地构建等待。

---

## [v1.0.0] - 2026-10-20

### 初始发布 (Initial Release)
- **6 大现代化测试架构层级完整实现**：
  - 【层级 1: 宿主工具】原生支持 Wireshark、Apifox、VS Code、Docker、Git，支持国内 CDN 与官方源自动切换。
  - 【层级 2: 编排与存储】Docker Compose 调度 PostgreSQL 16 数据库与 Prism HTTP Mock 服务。
  - 【层级 3: 测试运行时】Dev Container 统一镜像 (`qa-runtime:local`)，内置 Python 3.12+、Playwright 完整浏览器驱动、k6 压测引擎及 apifox-cli。
  - 【层级 4: 移动端支撑】宿主 ADB 5037 透明跨主机端口桥接 + Appium Server 容器化混合模式。
  - 【层级 5: 缺陷管理】Jira SaaS REST API 自动化提单集成配置与 Pytest 失败用例自触发钩子。
  - 【层级 6: 持续集成】自动化运行 API 接口契约测试、Web Playwright 测试与 k6 高并发压测基线，生成全层级健康评分卡（Scorecard）。
- **双平台一键启动脚本**：
  - Windows 根目录 [`start.bat`](start.bat) 与 Linux 根目录 [`start.sh`](start.sh)。
- **开源许可证声明**：
  - 采用商业友好的 [Apache License 2.0](LICENSE)，附带标准 [NOTICE](NOTICE) 说明文件。
