@echo off
cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 goto no_python

python -c "import requests, playwright" >nul 2>nul
if errorlevel 1 goto install_deps

:run
echo [INFO] Starting bot_launcher.py...
python "bot_launcher.py"
pause
exit /b 0

:install_deps
echo [INFO] Installing requests and playwright...
pip install requests playwright
python -m playwright install chromium
goto run

:no_python
echo [ERROR] Python 3 not found in PATH! Install Python from python.org and check Add Python to PATH.
pause
exit /b 1
