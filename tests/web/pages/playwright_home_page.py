"""
Playwright 官网首页 Page Object Model 封装类
实现页面元素定位与页面行为的完全解耦
"""

import re
from playwright.sync_api import Page, Locator, expect
from .base_page import BasePage


class PlaywrightHomePage(BasePage):
    """Playwright.dev 官方网站页面对象"""

    URL = "https://playwright.dev/"

    # 元素定位器常量 (Locators)
    GET_STARTED_BUTTON = "text=Get started"
    NAVBAR_TITLE = ".navbar__title"
    SEARCH_BUTTON = "button.DocSearch-Button"
    MAIN_HEADING = "h1"

    def __init__(self, page: Page):
        super().__init__(page)

    def navigate(self) -> "PlaywrightHomePage":
        """导航至 Playwright 首页"""
        self.goto(self.URL)
        return self

    @property
    def get_started_btn(self) -> Locator:
        """获取快速开始按钮元素"""
        return self.find(self.GET_STARTED_BUTTON)

    def click_get_started(self):
        """点击快速开始按钮，跳转至安装文档页"""
        self.get_started_btn.click()

    def verify_page_loaded(self):
        """断言页面标题与核心按钮正常渲染"""
        expect(self.page).to_have_title(re.compile(r"Playwright"))
        expect(self.get_started_btn).to_be_visible()

    def verify_installation_heading(self):
        """断言进入文档页后的一级标题 (基于 Playwright Web-first 机制自动轮询等待)"""
        expect(self.find(self.MAIN_HEADING)).to_contain_text("Installation")

    def get_heading_text(self) -> str:
        """获取当前页面主标题内容"""
        return self.find(self.MAIN_HEADING).inner_text()
