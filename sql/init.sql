-- ==============================================================================
-- QA 现代化自动化测试工程 - 数据库初始化脚本 (Schema & Seed Data)
-- 容器启动时由 PostgreSQL /docker-entrypoint-initdb.d/ 机制全自动执行
-- ==============================================================================

-- 1. 用户与测试人员表 (与 OpenAPI Mock 契约数据结构严格对齐)
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL,
    role VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. 自动化测试用例清单表
CREATE TABLE IF NOT EXISTS test_cases (
    id SERIAL PRIMARY KEY,
    case_key VARCHAR(50) NOT NULL UNIQUE,
    title VARCHAR(200) NOT NULL,
    suite_type VARCHAR(50) NOT NULL,
    priority VARCHAR(20) DEFAULT 'P1',
    status VARCHAR(20) DEFAULT 'ACTIVE',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. 测试执行记录表 (用于持久化测试流水线执行指标)
CREATE TABLE IF NOT EXISTS test_executions (
    id SERIAL PRIMARY KEY,
    case_id INT REFERENCES test_cases(id) ON DELETE CASCADE,
    runner VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL,
    duration_ms INT NOT NULL,
    error_message TEXT,
    executed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ------------------------------------------------------------------------------
-- 种子数据初始化 (Seed Data)
-- ------------------------------------------------------------------------------
INSERT INTO users (id, username, email, role) VALUES
    (1001, 'test_engineer', 'qa_engineer@example.com', 'SDET'),
    (1002, 'dev_lead', 'dev_lead@example.com', 'Developer')
ON CONFLICT (id) DO NOTHING;

INSERT INTO test_cases (case_key, title, suite_type, priority, status) VALUES
    ('API-001', '测试辅助 Mock 服务健康状态接口', 'API', 'P0', 'ACTIVE'),
    ('API-002', '测试 Mock 服务获取 SDET 用户信息', 'API', 'P1', 'ACTIVE'),
    ('DB-001', '验证独立容器 PostgreSQL 连接与数据查询', 'DB', 'P0', 'ACTIVE'),
    ('WEB-001', 'Playwright Web 端首页渲染与导航测试 (POM)', 'WEB', 'P0', 'ACTIVE'),
    ('PERF-001', 'k6 高并发接口阶梯性能压测基线', 'PERF', 'P1', 'ACTIVE')
ON CONFLICT (case_key) DO NOTHING;

INSERT INTO test_executions (case_id, runner, status, duration_ms) VALUES
    (1, 'qa-test-runner', 'PASSED', 350),
    (2, 'qa-test-runner', 'PASSED', 280),
    (3, 'qa-test-runner', 'PASSED', 150)
ON CONFLICT DO NOTHING;
