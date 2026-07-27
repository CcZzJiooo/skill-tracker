@echo off
chcp 65001 >nul
setlocal
title 创建桌面快捷方式 — Skill Tracker

echo.
echo 技能追踪器 (Skill Tracker)
echo ==========================
echo.
echo 正在为您生成桌面与开始菜单快捷方式...
echo.

where powershell >nul 2>&1
if errorlevel 1 (
  echo 未找到 PowerShell，无法自动创建快捷方式。
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\manage-shortcut.ps1" -Action CreateDesktopShortcut -CreateStartMenu
if errorlevel 1 (
  echo.
  echo 创建桌面快捷方式失败。
  pause
  exit /b 1
)

echo.
echo ===================================================
echo [成功] 已在您的桌面与开始菜单生成『技能追踪器』快捷方式！
echo 以后无需手动打开文件夹，在桌面双击『技能追踪器』图标即可直接运行。
echo ===================================================
echo.
pause
exit /b 0
