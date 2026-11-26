import ctypes
import csv
import io
import json
import os
import random
import subprocess
import time
import urllib.parse
import requests
from playwright.sync_api import sync_playwright

ACCOUNTS_FILE = "accounts.txt"
COOKIES_FILE = "cookies.json"
MAIN_ACCOUNT = "Blazpex82"  # <-- НИК ИЛИ USER ID ОСНОВНОГО АККАУНТА
SIGNAL_FILE = r"C:\Users\dudch\AppData\Local\Real\workspace\trade_done.txt"  # <-- УКАЖИ ПУТЬ К WORKSPACE ЭКЗЕКЬЮТОРА
MAX_WAIT_SECONDS = 40      # Макс. ожидание на один аккаунт (сек)
PAUSE_BETWEEN_ACCS = 4      # Пауза между аккаунтами (сек)


def enable_multi_instance():
    return ctypes.windll.kernel32.CreateMutexW(None, True, "ROBLOX_singletonEvent")


def get_roblox_pids() -> set[int]:
    pids = set()
    try:
        out = subprocess.check_output(
            ["tasklist", "/FI", "IMAGENAME eq RobloxPlayerBeta.exe", "/FO", "CSV", "/NH"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        for row in csv.reader(io.StringIO(out)):
            if len(row) >= 2 and row[0].lower() == "robloxplayerbeta.exe":
                if row[1].isdigit():
                    pids.add(int(row[1]))
    except Exception:
        pass
    return pids


def kill_alt_roblox(protected_pids: set[int]):
    current_pids = get_roblox_pids()
    for pid in current_pids:
        if pid not in protected_pids:
            subprocess.run(
                ["taskkill", "/F", "/PID", str(pid)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )


def resolve_user_id(account: str) -> int:
    account = str(account).strip()
    if account.isdigit():
        return int(account)

    r = requests.post(
        "https://users.roblox.com/v1/usernames/users",
        json={"usernames": [account], "excludeBannedUsers": False},
        timeout=10,
    )
    r.raise_for_status()
    data = r.json().get("data", [])
    if not data:
        raise RuntimeError(f"Аккаунт '{account}' не найден в Roblox.")
    return int(data[0]["id"])


def load_accounts():
    if not os.path.exists(ACCOUNTS_FILE):
        with open(ACCOUNTS_FILE, "w", encoding="utf-8") as f:
            f.write("login1 password1\nlogin2 password2\n")
        print(f"Создан шаблон {ACCOUNTS_FILE}. Заполни его (логин пробел пароль) и перезапусти.")
        return []

    accs = []
    with open(ACCOUNTS_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(None, 1)
            if len(parts) == 2:
                accs.append((parts[0], parts[1]))
    return accs


def load_cookies():
    if not os.path.exists(COOKIES_FILE):
        return {}
    try:
        with open(COOKIES_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def save_cookies(cookies_map):
    with open(COOKIES_FILE, "w", encoding="utf-8") as f:
        json.dump(cookies_map, f, ensure_ascii=False, indent=2)


def fetch_cookie_via_browser(username: str, password: str):
    print(f"  -> Открываю браузер для {username} (нужно один раз пройти капчу/2FA)...")
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False)
        context = browser.new_context()
        page = context.new_page()
        page.goto("https://www.roblox.com/login", wait_until="domcontentloaded")

        try:
            page.fill("#login-username", username, timeout=10_000)
            page.fill("#login-password", password, timeout=10_000)
            page.press("#login-password", "Enter")
        except Exception:
            print("  -> Автозаполнение не сработало, введи данные или нажми Log In вручную.")

        try:
            page.wait_for_url("**/home**", timeout=180_000)
            cookies = context.cookies("https://www.roblox.com")
            roblo = next((c["value"] for c in cookies if c["name"] == ".ROBLOSECURITY"), None)
            if roblo:
                print(f"  -> Кука для {username} успешно сохранена!")
            return roblo
        except Exception as e:
            print(f"  -> Не удалось войти в {username}: {e}")
            return None
        finally:
            context.close()
            browser.close()


def get_auth_ticket(cookie: str):
    session = requests.Session()
    session.cookies.set(".ROBLOSECURITY", cookie, domain=".roblox.com")
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        "Origin": "https://www.roblox.com",
        "Referer": "https://www.roblox.com/",
        "Content-Type": "application/json",
    }

    r1 = session.post("https://auth.roblox.com/v1/authentication-ticket", headers=headers, json={}, timeout=10)
    csrf = r1.headers.get("x-csrf-token")
    if not csrf:
        print(f"  -> [DEBUG] Нет CSRF-токена | Статус: {r1.status_code} | Ответ: {r1.text[:150]}")
        return None

    headers["x-csrf-token"] = csrf
    r2 = session.post("https://auth.roblox.com/v1/authentication-ticket", headers=headers, json={}, timeout=10)
    ticket = r2.headers.get("rbx-authentication-ticket")
    if not ticket:
        print(f"  -> [DEBUG] Нет AuthTicket | Статус: {r2.status_code} | Ответ: {r2.text[:150]}")
    return ticket


def launch_follow_user(ticket: str, target_user_id: int):
    launch_time = int(time.time() * 1000)
    tracker_id = random.randint(100000000000, 999999999999)
    launcher_url = urllib.parse.quote(
        f"https://assetgame.roblox.com/game/PlaceLauncher.ashx?request=RequestFollowUser&browserTrackerId={tracker_id}&userId={target_user_id}",
        safe="",
    )
    uri = (
        f"roblox-player:1+launchmode:play+gameinfo:{ticket}"
        f"+launchtime:{launch_time}"
        f"+placelauncherurl:{launcher_url}"
        f"+browsertrackerid:{tracker_id}+robloxLocale:en_us+gameLocale:en_us"
    )
    os.startfile(uri)


def main():
    _mutex = enable_multi_instance()

    accounts = load_accounts()
    if not accounts:
        return

    try:
        target_user_id = resolve_user_id(MAIN_ACCOUNT)
    except Exception as e:
        print(f"Ошибка получения UserId для '{MAIN_ACCOUNT}': {e}")
        return

    protected_pids = get_roblox_pids()
    if protected_pids:
        print(f"Защищённые окна основы (PID): {protected_pids}")
    else:
        print("Окно основы пока не обнаружено. Если откроешь его позже — перезапусти скрипт.")

    cookies_map = load_cookies()
    print(f"Загружено аккаунтов: {len(accounts)} | Цель (основа): {MAIN_ACCOUNT} (ID: {target_user_id})")

    while True:
        for username, password in accounts:
            print(f"\n[{time.strftime('%H:%M:%S')}] Аккаунт: {username}")
            kill_alt_roblox(protected_pids)
            time.sleep(2)

            cookie = cookies_map.get(username)
            ticket = get_auth_ticket(cookie) if cookie else None

            if not ticket:
                cookie = fetch_cookie_via_browser(username, password)
                if not cookie:
                    print(f"  -> Пропускаю {username}...")
                    continue
                cookies_map[username] = cookie
                save_cookies(cookies_map)
                ticket = get_auth_ticket(cookie)

            if not ticket:
                print(f"  -> Не удалось получить AuthTicket для {username}, пропуск.")
                continue

            if os.path.exists(SIGNAL_FILE):
                try:
                    os.remove(SIGNAL_FILE)
                except Exception:
                    pass

            launch_follow_user(ticket, target_user_id)
            print(f"  -> Захожу к {MAIN_ACCOUNT}... Жду завершения трейда (до {MAX_WAIT_SECONDS}с).")

            deadline = time.time() + MAX_WAIT_SECONDS
            got_signal = False
            while time.time() < deadline:
                if os.path.exists(SIGNAL_FILE):
                    try:
                        with open(SIGNAL_FILE, "r", encoding="utf-8") as sf:
                            print(f"  -> Сигнал получен: {sf.read().strip()}")
                        os.remove(SIGNAL_FILE)
                    except Exception:
                        pass
                    got_signal = True
                    break
                time.sleep(1)

            if not got_signal:
                print(f"  -> Таймаут ({MAX_WAIT_SECONDS}с) для {username}, переключаю дальше.")

            print(f"  -> Закрываю твинк {username}...")
            kill_alt_roblox(protected_pids)
            time.sleep(PAUSE_BETWEEN_ACCS)


if __name__ == "__main__":
    main()
