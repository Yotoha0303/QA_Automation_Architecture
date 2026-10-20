"""
Web 自动化测试 Page Object Model (POM) 页面对象模块
"""

from .base_page import BasePage
from .playwright_home_page import PlaywrightHomePage

__all__ = ["BasePage", "PlaywrightHomePage"]
