import pytest
import requests
import psycopg2

def test_mock_service_health():
    """测试辅助 Mock 服务 (Prism 容器) 健康检查接口"""
    url = "http://qa-mock-service:4010/api/v1/health"
    try:
        resp = requests.get(url, timeout=5)
    except requests.exceptions.ConnectionError:
        # 本地非容器直连时尝试 localhost
        resp = requests.get("http://localhost:4010/api/v1/health", timeout=5)
    assert resp.status_code == 200
    assert resp.json().get("status") == "UP"

def test_mock_get_user_info():
    """测试通过 Mock 服务获取用户信息"""
    url = "http://qa-mock-service:4010/api/v1/users/1001"
    try:
        resp = requests.get(url, timeout=5)
    except requests.exceptions.ConnectionError:
        resp = requests.get("http://localhost:4010/api/v1/users/1001", timeout=5)
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("username") == "test_engineer"
    assert data.get("role") == "SDET"

def test_postgres_connection():
    """验证独立容器 PostgreSQL 数据库连接与读写"""
    host = "qa-postgres"
    try:
        conn = psycopg2.connect(
            host=host, port=5432, user="qa_admin", password="QAPassword123!", dbname="qa_testdb", connect_timeout=3
        )
    except psycopg2.OperationalError:
        conn = psycopg2.connect(
            host="localhost", port=5432, user="qa_admin", password="QAPassword123!", dbname="qa_testdb", connect_timeout=3
        )
    cur = conn.cursor()
    cur.execute("SELECT 1;")
    result = cur.fetchone()
    cur.close()
    conn.close()
    assert result[0] == 1


def test_postgres_init_schema_and_seed_data():
    """验证挂载的数据库初始化 SQL 脚本执行与预置种子数据"""
    host = "qa-postgres"
    try:
        conn = psycopg2.connect(
            host=host, port=5432, user="qa_admin", password="QAPassword123!", dbname="qa_testdb", connect_timeout=3
        )
    except psycopg2.OperationalError:
        conn = psycopg2.connect(
            host="localhost", port=5432, user="qa_admin", password="QAPassword123!", dbname="qa_testdb", connect_timeout=3
        )
    cur = conn.cursor()
    # 验证初始化的用户表数据
    cur.execute("SELECT username, role FROM users WHERE id = 1001;")
    user = cur.fetchone()
    assert user is not None
    assert user[0] == "test_engineer"
    assert user[1] == "SDET"

    # 验证初始化的测试用例清单表数据
    cur.execute("SELECT COUNT(*) FROM test_cases;")
    count = cur.fetchone()[0]
    assert count >= 5
    cur.close()
    conn.close()

