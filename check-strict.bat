@echo off
chcp 65001 > nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\check.ps1" -ToolDir "%~dp0." -Strict
pause
