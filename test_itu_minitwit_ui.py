import os
import time
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from models import User
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

GUI_URL      = os.environ.get("GUI_URL",      "http://minitwit:5000")
SELENIUM_HUB = os.environ.get("SELENIUM_HUB", "http://selenium:4444/wd/hub")
DATABASE_URL = os.environ.get("DATABASE_URL",  "sqlite:////app/tmp/minitwit.db")

def _register_user_via_gui(driver, data):
    driver.get(GUI_URL + "/register")
    wait = WebDriverWait(driver, 5)
    wait.until(EC.presence_of_all_elements_located((By.CLASS_NAME, "actions")))
    input_fields = driver.find_elements(By.TAG_NAME, "input")
    for idx, str_content in enumerate(data):
        input_fields[idx].send_keys(str_content)
    input_fields[4].send_keys(Keys.RETURN)
    wait = WebDriverWait(driver, 5)
    flashes = wait.until(EC.presence_of_all_elements_located((By.CLASS_NAME, "flashes")))
    return flashes

def _get_user_by_name(name):
    engine = create_engine(DATABASE_URL)
    Session = sessionmaker(bind=engine)
    session = Session()
    user = session.query(User).filter(User.username == name).first()
    session.close()
    return user

def _delete_user_by_name(name):
    engine = create_engine(DATABASE_URL)
    Session = sessionmaker(bind=engine)
    session = Session()
    user = session.query(User).filter(User.username == name).first()
    if user:
        session.delete(user)
        session.commit()
    session.close()

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
    generated_msg = _register_user_via_gui(driver, ["Me", "me@some.where", "secure123", "secure123"])[0].text
    expected_msg = "You were successfully registered and can login now"
    assert generated_msg == expected_msg
    driver.quit()
    # cleanup, make test case idempotent
    _delete_user_by_name("Me")

def test_register_user_via_gui_and_check_db_entry():
    """
    This is an end-to-end test. Before registering a user via the UI, it checks that no such user exists in the
    database yet. After registering a user, it checks that the respective user appears in the database.
    """
    driver = _make_driver()
    assert _get_user_by_name("Me") == None
    generated_msg = _register_user_via_gui(driver, ["Me", "me@some.where", "secure123", "secure123"])[0].text
    expected_msg = "You were successfully registered and can login now"
    assert generated_msg == expected_msg
    assert _get_user_by_name("Me").username == "Me"
    driver.quit()
    # cleanup, make test case idempotent
    _delete_user_by_name("Me")
