@echo off
set SCRIPT_DIR=%~dp0..
net session >nul 2>&1
if not %errorlevel% == 0 (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\app\GameAutomationRunner.ps1" -IgnoreEnabled -SkipBetterGI -SkipMaaEnd -SkipMAA
pause
