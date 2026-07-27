<#
.SYNOPSIS
  Automated test suite for manage-shortcut.ps1 and desktop launcher features.
#>

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ShortcutScript = Join-Path $RepoRoot "scripts\manage-shortcut.ps1"
$DesktopBat = Join-Path $RepoRoot "创建桌面快捷方式.bat"

Write-Host "[Test] 1. Checking script and batch files exist..."
if (-not (Test-Path -LiteralPath $ShortcutScript)) { throw "manage-shortcut.ps1 not found." }
if (-not (Test-Path -LiteralPath $DesktopBat)) { throw "创建桌面快捷方式.bat not found." }

Write-Host "[Test] 2. Testing CreateDesktopShortcut & CreateStartMenu..."
& powershell -NoProfile -ExecutionPolicy Bypass -File "`"$ShortcutScript`"" -Action CreateDesktopShortcut -CreateStartMenu
$status = & powershell -NoProfile -ExecutionPolicy Bypass -File "`"$ShortcutScript`"" -Action GetStatus | ConvertFrom-Json
if (-not $status.desktopShortcut) { throw "Desktop shortcut creation failed." }
if (-not $status.startMenuShortcut) { throw "Start Menu shortcut creation failed." }
Write-Host "  -> Desktop & Start Menu shortcuts verified."

Write-Host "[Test] 3. Testing EnableAutoStart & DisableAutoStart..."
& powershell -NoProfile -ExecutionPolicy Bypass -File "`"$ShortcutScript`"" -Action EnableAutoStart
$status = & powershell -NoProfile -ExecutionPolicy Bypass -File "`"$ShortcutScript`"" -Action GetStatus | ConvertFrom-Json
if (-not $status.autoStart) { throw "AutoStart enable failed." }

& powershell -NoProfile -ExecutionPolicy Bypass -File "`"$ShortcutScript`"" -Action DisableAutoStart
$status = & powershell -NoProfile -ExecutionPolicy Bypass -File "`"$ShortcutScript`"" -Action GetStatus | ConvertFrom-Json
if ($status.autoStart) { throw "AutoStart disable failed." }
Write-Host "  -> AutoStart enable & disable verified."

Write-Host "[Test] 4. Cleaning up Desktop shortcut..."
& powershell -NoProfile -ExecutionPolicy Bypass -File "`"$ShortcutScript`"" -Action RemoveDesktopShortcut
$status = & powershell -NoProfile -ExecutionPolicy Bypass -File "`"$ShortcutScript`"" -Action GetStatus | ConvertFrom-Json
if ($status.desktopShortcut) { throw "Desktop shortcut cleanup failed." }
Write-Host "  -> Desktop shortcut cleanup verified."

Write-Host "=== PASS === All shortcut tests passed cleanly!"
