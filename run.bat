@echo off
echo Running Skill Tracker collector...
powershell -ExecutionPolicy Bypass -File "%~dp0collect.ps1"
echo.
echo Opening dashboard...
start "" "%~dp0dashboard\index.html"
pause
