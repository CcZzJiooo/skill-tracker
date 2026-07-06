@echo off
setlocal
title Skill Tracker

echo.
echo Skill Tracker
echo =============
echo.
echo Step 1/2: collecting local skill telemetry...
echo.

where powershell >nul 2>&1
if errorlevel 1 (
  echo PowerShell was not found. Opening the demo dashboard instead.
  goto open_dashboard
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0collect.ps1"
if errorlevel 1 (
  echo.
  echo Collector did not finish.
  echo This is usually OK for first-time users who do not have supported AI tool logs yet.
  echo The dashboard will open with built-in demo data.
)

:open_dashboard
echo.
echo Step 2/2: opening dashboard in your browser...
start "" "%~dp0dashboard\index.html"
echo.
echo If the browser did not open, open this file manually:
echo %~dp0dashboard\index.html
echo.
pause
