import re
import pytest
from playwright.sync_api import Page, expect

try:
    from tests.web.pages.playwright_home_page import PlaywrightHomePage
except ImportError:
    from pages.playwright_home_page import PlaywrightHomePage


def test_playwright_web_navigation(page: Page):
    """Playwright 统一运行时测试: 基础页面访问与渲染验证"""
    page.goto("https://playwright.dev/")
    expect(page).to_have_title(re.compile(r"Playwright"))

    get_started = page.locator("text=Get started")
    expect(get_started).to_be_visible()


def test_playwright_web_pom_workflow(page: Page):
    """
    Playwright Web 自动化测试: Page Object Model (POM) 设计模式范例
    将页面定位器和行为封装至 PlaywrightHomePage，测试用例专注于业务逻辑与状态断言
    """
    home_page = PlaywrightHomePage(page)

    # 1. 导航至首页并验证加载
    home_page.navigate()
    home_page.verify_page_loaded()

    # 2. 点击快速开始按钮，验证页面交互跳转
    home_page.click_get_started()
    expect(page).to_have_url(re.compile(r"/docs/intro"))

    # 3. 验证进入安装页面后的一级标题 (Playwright Web-first 机制自动轮询等待)
    home_page.verify_installation_heading()

