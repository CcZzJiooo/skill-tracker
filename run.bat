@echo off
setlocal
title Skill Tracker

echo.
echo Skill Tracker
echo =============
echo.
echo Reading local AI-agent logs and opening Skill Tracker...
echo.

where powershell >nul 2>&1
if errorlevel 1 (
  echo PowerShell was not found. Skill Tracker cannot read local logs without it.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-dashboard.ps1"
if errorlevel 1 (
  echo.
  echo Skill Tracker failed to start.
  echo Try running this command from PowerShell in this folder:
  echo powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-dashboard.ps1"
  pause
  exit /b 1
)
exit /b 0
