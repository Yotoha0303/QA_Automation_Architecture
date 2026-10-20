"""
Web 自动化测试基础页面对象 (BasePage)
封装通用的 Playwright 页面基础交互与等待逻辑
"""

from playwright.sync_api import Page, Locator, Response
from typing import Optional


class BasePage:
    """页面对象模型基类，提供通用页面操作封装"""

    def __init__(self, page: Page):
        self.page = page

    def goto(self, url: str) -> Optional[Response]:
        """访问指定 URL 页面"""
        return self.page.goto(url, wait_until="domcontentloaded")

    def get_title(self) -> str:
        """获取当前页面标题"""
        return self.page.title()

    def get_url(self) -> str:
        """获取当前页面 URL"""
        return self.page.url

    def find(self, selector: str) -> Locator:
        """定位页面元素"""
        return self.page.locator(selector)

    def click(self, selector: str):
        """点击指定页面元素"""
        self.page.locator(selector).click()
