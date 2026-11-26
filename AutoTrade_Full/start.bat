@echo off
chcp 65001 >nul
python -c "import requests, playwright" 2>nul || (
    echo Установка библиотек...
    pip install requests playwright
    playwright install chromium
)
python bot_launcher.py
pause
