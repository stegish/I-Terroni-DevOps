import os
import time
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

GUI_URL = os.environ.get("GUI_URL", "http://minitwit:5000")
SELENIUM_HUB = os.environ.get("SELENIUM_HUB", "http://selenium:4444/wd/hub")


def _register_user_via_gui(driver, data):
    driver.get(GUI_URL + "/register")
    wait = WebDriverWait(driver, 10)
    wait.until(EC.presence_of_all_elements_located((By.CLASS_NAME, "actions")))
    input_fields = driver.find_elements(By.TAG_NAME, "input")
    for idx, str_content in enumerate(data):
        input_fields[idx].send_keys(str_content)
    input_fields[3].send_keys(Keys.RETURN)
    # Pyramid redirects to /login after register, flash message appears there
    wait = WebDriverWait(driver, 10)
    flashes = wait.until(
        EC.presence_of_all_elements_located((By.CLASS_NAME, "flashes"))
    )
    return flashes


def _make_driver():
    options = webdriver.ChromeOptions()
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    for attempt in range(15):
        try:
            driver = webdriver.Remote(command_executor=SELENIUM_HUB, options=options)
            driver.implicitly_wait(5)
            return driver
        except Exception:
            print(f"Waiting for Selenium hub... attempt {attempt + 1}/15")
            time.sleep(3)
    raise RuntimeError(f"Selenium hub at {SELENIUM_HUB} never became available.")


def test_register_user_via_gui():
    """
    This is a UI test. It only interacts with the UI that is rendered in the browser and checks that visual
    responses that users observe are displayed.
    """
    driver = _make_driver()
    try:
        generated_msg = _register_user_via_gui(
            driver, ["Me", "me@some.where", "secure123", "secure123"]
        )[0].text
        expected_msg = "You were successfully registered and can login now"
        assert generated_msg == expected_msg
    finally:
        driver.quit()


def test_register_user_via_gui_and_check_db_entry():
    """
    This is an end-to-end test. Registers a user via the UI and verifies the user
    exists in the system by logging in successfully afterwards.
    Note: direct DB access is not possible since the test container and app container
    do not share a filesystem, so verification is done via the UI.
    """
    driver = _make_driver()
    try:
        generated_msg = _register_user_via_gui(
            driver, ["Me2", "me2@some.where", "secure123", "secure123"]
        )[0].text
        expected_msg = "You were successfully registered and can login now"
        assert generated_msg == expected_msg

        # Verify user exists by logging in successfully
        driver.get(GUI_URL + "/login")
        driver.find_element(By.NAME, "username").send_keys("Me2")
        driver.find_element(By.NAME, "password").send_keys("secure123")
        driver.find_element(By.NAME, "password").send_keys(Keys.RETURN)
        wait = WebDriverWait(driver, 10)
        flashes = wait.until(
            EC.presence_of_all_elements_located((By.CLASS_NAME, "flashes"))
        )
        assert "You were logged in" in flashes[0].text
    finally:
        driver.quit()
