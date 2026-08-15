@echo off
chcp 65001 > nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\organize.ps1" -ToolDir "%~dp0."
pause
