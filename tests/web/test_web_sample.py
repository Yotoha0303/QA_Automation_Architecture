import re

import pytest
from playwright.sync_api import Page, expect

def test_playwright_web_navigation(page: Page):
    """Playwright 统一运行时测试: 访问示例网页验证标题与渲染"""
    page.goto("https://playwright.dev/")
    expect(page).to_have_title(re.compile(r"Playwright"))
    
    # 获取快速起步按钮
    get_started = page.locator("text=Get started")
    expect(get_started).to_be_visible()
