<#
.SYNOPSIS
  Skill Tracker — Desktop Shortcut & Startup Management for Windows.

.DESCRIPTION
  Creates, checks, and removes zero-false-positive native Windows .lnk shortcuts
  on the User's Desktop, Start Menu, and Startup folder.
#>
param(
    [ValidateSet("CreateDesktopShortcut", "CreateStartMenuShortcut", "EnableAutoStart", "DisableAutoStart", "RemoveDesktopShortcut", "GetStatus")]
    [string]$Action = "CreateDesktopShortcut",
    [switch]$CreateStartMenu
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$StartDashboardPath = Join-Path $RepoRoot "start-dashboard.ps1"

$DesktopPath = [Environment]::GetFolderPath("Desktop")
$StartMenuPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$StartupPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"

$ShortcutName = "技能追踪器.lnk"
$DesktopShortcutFile = Join-Path $DesktopPath $ShortcutName
$StartMenuShortcutFile = Join-Path $StartMenuPath $ShortcutName
$StartupShortcutFile = Join-Path $StartupPath $ShortcutName

function New-NativeShortcut {
    param(
        [string]$TargetPath,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$ShortcutFilePath,
        [string]$Description,
        [string]$IconLocation,
        [int]$WindowStyle = 7 # 7 = Minimized / Hidden
    )

    $ws = New-Object -ComObject WScript.Shell
    $shortcut = $ws.CreateShortcut($ShortcutFilePath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = $Description
    $shortcut.WindowStyle = $WindowStyle
    if ($IconLocation) {
        $shortcut.IconLocation = $IconLocation
    }
    $shortcut.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws) | Out-Null
}

function Get-ShortcutStatus {
    $desktopExists = Test-Path -LiteralPath $DesktopShortcutFile -PathType Leaf
    $startMenuExists = Test-Path -LiteralPath $StartMenuShortcutFile -PathType Leaf
    $autoStartExists = Test-Path -LiteralPath $StartupShortcutFile -PathType Leaf

    return [PSCustomObject]@{
        desktopShortcut = $desktopExists
        startMenuShortcut = $startMenuExists
        autoStart = $autoStartExists
        desktopPath = $DesktopShortcutFile
        startupPath = $StartupShortcutFile
    }
}

$RunBatPath = Join-Path $RepoRoot "run.bat"
$IcoFile = Join-Path $RepoRoot "skill-tracker.ico"
$icon = if (Test-Path -LiteralPath $IcoFile) { "$IcoFile,0" } else { "shell32.dll,13" }

switch ($Action) {
    "CreateDesktopShortcut" {
        New-NativeShortcut `
            -TargetPath $RunBatPath `
            -Arguments "" `
            -WorkingDirectory $RepoRoot `
            -ShortcutFilePath $DesktopShortcutFile `
            -Description "技能追踪器 — 自动搜集与可视化 AI 代理技能调用日志" `
            -IconLocation $icon `
            -WindowStyle 1

        if ($CreateStartMenu) {
            New-NativeShortcut `
                -TargetPath $RunBatPath `
                -Arguments "" `
                -WorkingDirectory $RepoRoot `
                -ShortcutFilePath $StartMenuShortcutFile `
                -Description "技能追踪器 — 自动搜集与可视化 AI 代理技能调用日志" `
                -IconLocation $icon `
                -WindowStyle 1
        }

        Write-Host "成功在桌面创建快捷方式: $DesktopShortcutFile"
        if ($CreateStartMenu) {
            Write-Host "成功在开始菜单创建快捷方式: $StartMenuShortcutFile"
        }
    }

    "CreateStartMenuShortcut" {
        New-NativeShortcut `
            -TargetPath $RunBatPath `
            -Arguments "" `
            -WorkingDirectory $RepoRoot `
            -ShortcutFilePath $StartMenuShortcutFile `
            -Description "技能追踪器 — 自动搜集与可视化 AI 代理技能调用日志" `
            -IconLocation $icon `
            -WindowStyle 1
        Write-Host "成功在开始菜单创建快捷方式: $StartMenuShortcutFile"
    }

    "EnableAutoStart" {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$StartDashboardPath`" -NoBrowser"
        New-NativeShortcut `
            -TargetPath "powershell.exe" `
            -Arguments $arguments `
            -WorkingDirectory $RepoRoot `
            -ShortcutFilePath $StartupShortcutFile `
            -Description "技能追踪器 (开机后台监听)" `
            -IconLocation $icon `
            -WindowStyle 7
        Write-Host "成功配置开机后台自启: $StartupShortcutFile"
    }

    "DisableAutoStart" {
        if (Test-Path -LiteralPath $StartupShortcutFile) {
            Remove-Item -LiteralPath $StartupShortcutFile -Force
            Write-Host "已取消开机自启。"
        } else {
            Write-Host "未设置开机自启。"
        }
    }

    "RemoveDesktopShortcut" {
        if (Test-Path -LiteralPath $DesktopShortcutFile) {
            Remove-Item -LiteralPath $DesktopShortcutFile -Force
            Write-Host "已删除桌面快捷方式。"
        }
    }

    "GetStatus" {
        $status = Get-ShortcutStatus
        $status | ConvertTo-Json
    }
}
