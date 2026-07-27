@echo off
chcp 65001 >nul
setlocal
title Skill Tracker

echo.
echo Skill Tracker
echo =============
echo.
echo 正在自动扫描全量 AI 工具日志并启动 Skill Tracker...
echo.

where powershell >nul 2>&1
if errorlevel 1 (
  echo 未找到 PowerShell，Skill Tracker 无法读取本地日志。
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-dashboard.ps1" %*
if errorlevel 1 (
  echo.
  echo Skill Tracker 启动失败。
  echo 请尝试在 PowerShell 中手动运行:
  echo powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-dashboard.ps1"
  pause
  exit /b 1
)
exit /b 0
