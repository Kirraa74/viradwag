import ctypes
import csv
import io
import json
import os
import random
import shutil
import subprocess
import sys
import time
import urllib.parse
import requests
from playwright.sync_api import sync_playwright

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(BASE_DIR, "config.txt")
COOKIES_FILE = os.path.join(BASE_DIR, "cookies.json")
SCRIPTS_DIR = os.path.join(BASE_DIR, "scripts")
SRC_LOADER = os.path.join(SCRIPTS_DIR, "kirraa74_loader.luau")
SRC_AUTO = os.path.join(SCRIPTS_DIR, "auto.luau")


def enable_multi_instance():
    try:
        return ctypes.windll.kernel32.CreateMutexW(None, True, "ROBLOX_singletonEvent")
    except Exception:
        return None


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


def split_creds(s: str) -> list[str]:
    s = s.strip()
    if " " in s or "\t" in s:
        return s.split(None, 1)
    if ":" in s:
        return s.split(":", 1)
    return [s]


def parse_config() -> dict:
    cfg = {
        "main_account": "",
        "executor_dir": "AUTO",
        "max_wait": 75,
        "pause_between": 7,
        "inject_timeout": 25,
        "max_retries": 2,
        "accounts": [],
        "skins": [],
    }
    if not os.path.exists(CONFIG_FILE):
        return cfg

    section = None
    with open(CONFIG_FILE, "r", encoding="utf-8-sig") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#") or line.startswith("//") or line.startswith(";"):
                continue

            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1].strip().upper()
                continue

            if section == "SETTINGS":
                if "=" in line:
                    k, v = line.split("=", 1)
                    k = k.strip().upper()
                    v = v.strip().strip('"')
                    if k == "MAIN_ACCOUNT":
                        if v not in ("", "ВПИШИ_НИК_ОСНОВЫ", "MAIN_USERNAME_HERE"):
                            cfg["main_account"] = v.split()[0]
                    elif k == "EXECUTOR_DIR":
                        cfg["executor_dir"] = v or "AUTO"
                    elif k == "MAX_WAIT_SECONDS":
                        try:
                            cfg["max_wait"] = max(20, int(v))
                        except ValueError:
                            pass
                    elif k == "PAUSE_BETWEEN_ACCS":
                        try:
                            cfg["pause_between"] = max(1, int(v))
                        except ValueError:
                            pass
                    elif k == "INJECT_TIMEOUT":
                        try:
                            cfg["inject_timeout"] = max(10, int(v))
                        except ValueError:
                            pass
                    elif k in ("MAX_RETRIES", "RETRY_ON_TIMEOUT"):
                        try:
                            cfg["max_retries"] = max(0, min(10, int(v)))
                        except ValueError:
                            pass

            elif section == "ACCOUNTS":
                cookie = ""
                username = ""
                password = ""
                if "_|WARNING:" in line:
                    idx = line.index("_|WARNING:")
                    cookie = line[idx:].strip()
                    prefix = line[:idx].rstrip(":; \t")
                    parts = split_creds(prefix)
                    if len(parts) >= 1:
                        username = parts[0].strip()
                    if len(parts) >= 2:
                        password = parts[1].strip()
                else:
                    parts = split_creds(line)
                    if len(parts) >= 2:
                        username, password = parts[0].strip(), parts[1].strip()
                    elif len(parts) == 1:
                        username, password = parts[0].strip(), ""

                if username:
                    cfg["accounts"].append({
                        "username": username,
                        "password": password,
                        "cookie": cookie,
                    })

            elif section == "SKINS":
                cfg["skins"].append(line)

    return cfg


def save_executor_dir_to_config(new_dir: str):
    if not os.path.exists(CONFIG_FILE):
        return
    with open(CONFIG_FILE, "r", encoding="utf-8-sig") as f:
        lines = f.readlines()

    updated = False
    for i, line in enumerate(lines):
        if line.strip().upper().startswith("EXECUTOR_DIR"):
            lines[i] = f"EXECUTOR_DIR = {new_dir}\n"
            updated = True
            break

    if updated:
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            f.writelines(lines)


def is_valid_executor_dir(path: str) -> bool:
    if not path or not os.path.isdir(path):
        return False
    ws = os.path.join(path, "workspace")
    ae = os.path.join(path, "autoexec")
    return os.path.isdir(ws) or os.path.isdir(ae)


def detect_executor_dir(configured_dir: str) -> str:
    if configured_dir and configured_dir.upper() != "AUTO":
        if os.path.basename(configured_dir.rstrip("\\/")).lower() in ("workspace", "autoexec"):
            configured_dir = os.path.dirname(configured_dir.rstrip("\\/"))
        if os.path.isdir(configured_dir):
            return configured_dir

    local_app = os.environ.get("LOCALAPPDATA", "")
    roaming_app = os.environ.get("APPDATA", "")
    known_names = ["Real", "Wave", "Solara", "Xeno", "Swift", "Velocity", "AWP", "Zenith", "Seliware", "Argon"]

    candidates = []
    for base in (local_app, roaming_app):
        if not base or not os.path.isdir(base):
            continue
        for name in known_names:
            p = os.path.join(base, name)
            if is_valid_executor_dir(p):
                candidates.append(p)

    if not candidates and local_app and os.path.isdir(local_app):
        try:
            for entry in os.scandir(local_app):
                if entry.is_dir():
                    if os.path.isdir(os.path.join(entry.path, "workspace")) and os.path.isdir(os.path.join(entry.path, "autoexec")):
                        candidates.append(entry.path)
        except OSError:
            pass

    if len(candidates) == 1:
        print(f"[AUTO] Найден инжектор: {candidates[0]}")
        return candidates[0]
    elif len(candidates) > 1:
        print("\nНайдено несколько инжекторов:")
        for idx, c in enumerate(candidates, 1):
            print(f"  {idx}. {c}")
        choice = input("Выбери номер (Enter = 1): ").strip()
        if choice.isdigit() and 1 <= int(choice) <= len(candidates):
            chosen = candidates[int(choice) - 1]
        else:
            chosen = candidates[0]
        save_executor_dir_to_config(chosen)
        return chosen

    print("\n[НАСТРОЙКА] Не удалось автоматически найти папку инжектора.")
    print("Перетащи папку твоего инжектора (где лежат autoexec и workspace) в это окно и нажми Enter:")
    while True:
        user_path = input("Путь к папке инжектора: ").strip().strip('"')
        if os.path.basename(user_path.rstrip("\\/")).lower() in ("workspace", "autoexec"):
            user_path = os.path.dirname(user_path.rstrip("\\/"))
        if os.path.isdir(user_path):
            save_executor_dir_to_config(user_path)
            return user_path
        print("Папка не найдена, попробуй ещё раз.")


def sync_files_to_executor(executor_dir: str, force_trade_on: bool = True) -> tuple[str, str]:
    autoexec_dir = os.path.join(executor_dir, "autoexec")
    workspace_dir = os.path.join(executor_dir, "workspace")
    os.makedirs(autoexec_dir, exist_ok=True)
    os.makedirs(workspace_dir, exist_ok=True)

    if os.path.exists(SRC_LOADER):
        shutil.copy2(SRC_LOADER, os.path.join(autoexec_dir, "kirraa74_loader.luau"))
    else:
        raise FileNotFoundError(f"Не найден файл {SRC_LOADER}")

    if os.path.exists(SRC_AUTO):
        shutil.copy2(SRC_AUTO, os.path.join(workspace_dir, "auto.luau"))
    else:
        raise FileNotFoundError(f"Не найден файл {SRC_AUTO}")

    shutil.copy2(CONFIG_FILE, os.path.join(workspace_dir, "kirraa74_config.txt"))

    if force_trade_on:
        switch_file = os.path.join(workspace_dir, "kirraa74_autotrade_switch.txt")
        force_on_file = os.path.join(workspace_dir, "kirraa74_force_trade_on.txt")
        with open(switch_file, "w", encoding="utf-8") as f:
            f.write("1\n")
        with open(force_on_file, "w", encoding="utf-8") as f:
            f.write(str(int(time.time())) + "\n")

    return autoexec_dir, workspace_dir


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


def load_cookies() -> dict:
    if not os.path.exists(COOKIES_FILE):
        return {}
    try:
        with open(COOKIES_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def save_cookies(cookies_map: dict):
    with open(COOKIES_FILE, "w", encoding="utf-8") as f:
        json.dump(cookies_map, f, ensure_ascii=False, indent=2)


def fetch_cookie_via_browser(username: str, password: str):
    print(f"  -> Открываю браузер для {username} (нужно 1 раз войти / пройти капчу)...")
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False)
        context = browser.new_context()
        page = context.new_page()
        page.goto("https://www.roblox.com/login", wait_until="domcontentloaded")

        try:
            if username:
                page.fill("#login-username", username, timeout=10_000)
            if password:
                page.fill("#login-password", password, timeout=10_000)
                page.press("#login-password", "Enter")
        except Exception:
            print("  -> Автозаполнение не сработало, введи данные вручную.")

        try:
            page.wait_for_url("**/home**", timeout=180_000)
            cookies = context.cookies("https://www.roblox.com")
            roblo = next((c["value"] for c in cookies if c["name"] == ".ROBLOSECURITY"), None)
            if roblo:
                print(f"  -> Кука для {username} сохранена!")
            return roblo
        except Exception as e:
            print(f"  -> Не удалось войти в {username}: {e}")
            return None
        finally:
            context.close()
            browser.close()


def get_auth_ticket(cookie: str):
    if not cookie:
        return None
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
        return None

    headers["x-csrf-token"] = csrf
    r2 = session.post("https://auth.roblox.com/v1/authentication-ticket", headers=headers, json={}, timeout=10)
    return r2.headers.get("rbx-authentication-ticket")


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


def remove_if_exists(path: str):
    if os.path.exists(path):
        try:
            os.remove(path)
        except OSError:
            pass


def read_trade_signal(signal_file: str):
    if not os.path.exists(signal_file):
        return None
    try:
        with open(signal_file, "r", encoding="utf-8-sig") as sf:
            reason = sf.read().strip()
        os.remove(signal_file)
        return reason
    except OSError:
        return None


def run_single_alt(
    acc: dict,
    cfg: dict,
    target_user_id: int,
    protected_pids: set[int],
    cookies_map: dict,
    signal_file: str,
    inject_file: str,
):
    username = acc["username"]
    password = acc["password"]
    inline_cookie = acc["cookie"]
    max_attempts = 1 + cfg["max_retries"]

    for attempt in range(1, max_attempts + 1):
        suffix = f" (попытка {attempt}/{max_attempts})" if attempt > 1 else ""
        print(f"\n[{time.strftime('%H:%M:%S')}] Аккаунт: {username}{suffix}")
        kill_alt_roblox(protected_pids)
        time.sleep(2)

        cookie = inline_cookie or cookies_map.get(username)
        ticket = get_auth_ticket(cookie) if cookie else None

        if not ticket:
            cookie = fetch_cookie_via_browser(username, password)
            if not cookie:
                print(f"  -> Пропускаю {username}...")
                return
            cookies_map[username] = cookie
            save_cookies(cookies_map)
            ticket = get_auth_ticket(cookie)

        if not ticket:
            print(f"  -> Не удалось получить AuthTicket для {username}, пропуск.")
            return

        remove_if_exists(signal_file)
        remove_if_exists(inject_file)

        launch_follow_user(ticket, target_user_id)
        launch_ts = time.time()
        print(
            f"  -> Захожу к {cfg['main_account']}... "
            f"Жду инжект (до {cfg['inject_timeout']}с) и трейд (до {cfg['max_wait']}с)."
        )

        deadline = launch_ts + cfg["max_wait"]
        alt_spawned = False
        injected = False
        trade_succeeded = False
        fail_reason = f"таймаут ({cfg['max_wait']}с)"

        while time.time() < deadline:
            # 1. Проверяем сигнал завершения трейда
            reason = read_trade_signal(signal_file)
            if reason is not None:
                if "trade_closed" in reason.lower():
                    print(f"  -> Готово ({reason})")
                    trade_succeeded = True
                else:
                    fail_reason = f"трейд не состоялся ({reason})"
                break

            # 2. Проверяем подтверждение инжекта скрипта
            if not injected and os.path.exists(inject_file):
                injected = True
                remove_if_exists(inject_file)
                print("  -> Инжект прошёл! Жду переработку и трейд...")

            # 3. Контролируем процесс твинка (ловим краш/вылет Roblox)
            alt_pids = get_roblox_pids() - protected_pids
            if alt_pids:
                alt_spawned = True
            elif alt_spawned:
                # Процесс твинка исчез — даём 1.5с на случай, если trade_done.txt успел записаться
                time.sleep(1.5)
                reason = read_trade_signal(signal_file)
                if reason is not None and "trade_closed" in reason.lower():
                    print(f"  -> Готово ({reason})")
                    trade_succeeded = True
                else:
                    fail_reason = "Roblox крашнулся или закрылся до завершения трейда"
                break

            elapsed = time.time() - launch_ts

            # 4. Если окно Roblox вообще не появилось
            if not alt_spawned and elapsed >= max(20, cfg["inject_timeout"]):
                fail_reason = "окно Roblox твинка не запустилось"
                break

            # 5. Если окно открылось, но скрипт не заинжектился за INJECT_TIMEOUT
            if not injected and elapsed >= cfg["inject_timeout"]:
                fail_reason = f"скрипт не заинжектился за {cfg['inject_timeout']}с"
                break

            time.sleep(1)

        print(f"  -> Закрываю окно твинка {username}...")
        kill_alt_roblox(protected_pids)
        time.sleep(cfg["pause_between"])

        if trade_succeeded:
            return

        if attempt < max_attempts:
            print(f"  -> [ПЕРЕЗАПУСК] {fail_reason}. Захожу на {username} заново...")
        else:
            print(f"  -> [ПРОПУСК] {username}: {fail_reason}. Лимит попыток исчерпан, иду дальше.")


def main():
    if not os.path.exists(CONFIG_FILE):
        print(f"[ОШИБКА] Не найден файл {CONFIG_FILE}!")
        return

    cfg = parse_config()
    if not cfg["main_account"]:
        print("[ОШИБКА] Открой config.txt и впиши ник основного аккаунта в MAIN_ACCOUNT.")
        return

    if not cfg["accounts"]:
        print("[ОШИБКА] Открой config.txt и добавь аккаунты твинков в раздел [ACCOUNTS].")
        return

    executor_dir = detect_executor_dir(cfg["executor_dir"])
    autoexec_dir, workspace_dir = sync_files_to_executor(executor_dir)
    signal_file = os.path.join(workspace_dir, "trade_done.txt")
    inject_file = os.path.join(workspace_dir, "alt_injected.txt")

    print("[OK] Скрипты и config.txt синхронизированы с инжектором:")
    print(f"     autoexec : {autoexec_dir}")
    print(f"     workspace: {workspace_dir}")
    print("[OK] Кнопка ТРЕЙД автоматически включена.")

    _mutex = enable_multi_instance()

    if not get_roblox_pids():
        input("[INFO] Мульти-окно активно! Теперь зайди в игру с ОСНОВЫ и нажми Enter...")

    try:
        target_user_id = resolve_user_id(cfg["main_account"])
    except Exception as e:
        print(f"[ОШИБКА] Не удалось найти основу '{cfg['main_account']}' в Roblox: {e}")
        return

    protected_pids = get_roblox_pids()
    if protected_pids:
        print(f"[INFO] Защищены окна основы (PID): {protected_pids}")
    else:
        print("[ВНИМАНИЕ] Окно основы не найдено! Если основа не открыта — открой её и перезапусти start.bat.")

    cookies_map = load_cookies()
    print(f"[START] Основа: {cfg['main_account']} (ID: {target_user_id}) | Твинков: {len(cfg['accounts'])}")

    while True:
        cfg = parse_config()
        if not cfg["accounts"]:
            print("[WARN] В [ACCOUNTS] нет аккаунтов, жду 5с...")
            time.sleep(5)
            continue

        sync_files_to_executor(executor_dir, force_trade_on=False)

        for acc in cfg["accounts"]:
            run_single_alt(acc, cfg, target_user_id, protected_pids, cookies_map, signal_file, inject_file)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[STOP] Остановлено пользователем.")
        sys.exit(0)
