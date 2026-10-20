import pytest
from appium import webdriver
from appium.options.android import UiAutomator2Options

@pytest.mark.skip(reason="需要物理连接 Android 真机或已运行的模拟器，默认跳过")
def test_mobile_appium_hybrid_connection():
    """
    移动端支撑层 (混合架构):
    通过宿主机 ADB 转发或宿主机 Appium Server 驱动连接设备
    """
    options = UiAutomator2Options()
    options.platform_name = "Android"
    options.device_name = "Android_Device"
    options.automation_name = "UiAutomator2"
    options.app_package = "com.android.settings"
    options.app_activity = ".Settings"

    # 指向宿主机 Appium Server (混合模式)
    appium_server_url = "http://host.docker.internal:4723"

    driver = webdriver.Remote(appium_server_url, options=options)
    assert driver is not None
    driver.quit()
