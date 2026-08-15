@echo off
chcp 65001 >nul
setlocal
title Skill Tracker

echo.
echo Skill Tracker
echo =============
echo.
echo Starting Skill Tracker. Local data will continue syncing in the background.
echo.

where powershell >nul 2>&1
if errorlevel 1 (
  echo PowerShell was not found. Skill Tracker cannot read local logs without it.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-dashboard.ps1" %*
if errorlevel 1 (
  echo.
  echo Skill Tracker startup failed.
  echo Run this command in PowerShell to diagnose the problem:
  echo powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-dashboard.ps1"
  pause
  exit /b 1
)
exit /b 0
