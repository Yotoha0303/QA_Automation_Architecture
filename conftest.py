import os
import pytest
from dotenv import load_dotenv

# 加载环境变量
load_dotenv("config/jira_config.env")

JIRA_ENABLE = os.getenv("JIRA_ENABLE_AUTO_BUG", "false").lower() == "true"
JIRA_SERVER = os.getenv("JIRA_SERVER_URL")
JIRA_USER = os.getenv("JIRA_USER_EMAIL")
JIRA_TOKEN = os.getenv("JIRA_API_TOKEN")
JIRA_PROJECT = os.getenv("JIRA_PROJECT_KEY", "QA")


def report_bug_to_jira(test_name: str, error_details: str):
    """当测试失败时，通过官方 SaaS REST API 自动提交缺陷单"""
    if not JIRA_ENABLE or not JIRA_TOKEN:
        return
    try:
        from jira import JIRA
        jira_client = JIRA(server=JIRA_SERVER, basic_auth=(JIRA_USER, JIRA_TOKEN))
        issue_dict = {
            'project': {'key': JIRA_PROJECT},
            'summary': f'[自动化测试失败] 用例: {test_name}',
            'description': f'*执行失败详情:*\n```\n{error_details}\n```\n*提交来源*: 自动化回归流水线',
            'issuetype': {'name': 'Bug'},
        }
        new_issue = jira_client.create_issue(fields=issue_dict)
        print(f"\n[Jira] 已自动创建缺陷单: {new_issue.key} -> {JIRA_SERVER}/browse/{new_issue.key}")
    except Exception as e:
        print(f"\n[Jira] 自动提单失败: {e}")


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):
    outcome = yield
    report = outcome.get_result()
    if report.when == "call" and report.failed:
        error_msg = str(report.longrepr)
        report_bug_to_jira(item.nodeid, error_msg)
