@echo off
setlocal
title Skill Tracker

echo.
echo Skill Tracker
echo =============
echo.
echo Starting the stable local dashboard entry...
echo.

where powershell >nul 2>&1
if errorlevel 1 (
  echo PowerShell was not found. Opening the demo dashboard instead.
  goto open_dashboard
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-dashboard.ps1"
if errorlevel 1 (
  echo.
  echo Skill Tracker failed to start.
  echo Try running this command from PowerShell:
  echo powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-dashboard.ps1"
  pause
)
exit /b 0

:open_dashboard
start "" "%~dp0dashboard\index.html"
exit /b 0
