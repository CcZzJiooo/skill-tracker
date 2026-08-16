param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot "tools/platform-paths.psm1"
Import-Module $modulePath -Force

function Assert-Equal {
    param([string]$Actual, [string]$Expected, [string]$Message)
    $normalizedActual = $Actual.Replace('\', '/')
    $normalizedExpected = $Expected.Replace('\', '/')
    if ($normalizedActual -ne $normalizedExpected) { throw "$Message Expected '$Expected', got '$Actual'." }
}

$linuxHome = [System.IO.Path]::Combine([System.IO.Path]::GetPathRoot((Get-Location).Path), "home", "tester")
$previousXdgConfigHome = $env:XDG_CONFIG_HOME
$previousXdgDataHome = $env:XDG_DATA_HOME
try {
    Remove-Item Env:XDG_CONFIG_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:XDG_DATA_HOME -ErrorAction SilentlyContinue

    $linux = Get-SkillTrackerPlatformPaths -Platform Linux -UserHome $linuxHome
    Assert-Equal $linux.AppData ([System.IO.Path]::Combine($linuxHome, ".config")) "Linux config root mismatch."
    Assert-Equal $linux.LocalAppData ([System.IO.Path]::Combine($linuxHome, ".local", "share")) "Linux data root mismatch."
    Assert-Equal $linux.EditorGlobalStorageRoots[0] ([System.IO.Path]::Combine($linuxHome, ".config", "Code", "User", "globalStorage")) "Linux VS Code storage mismatch."

    $env:XDG_CONFIG_HOME = [System.IO.Path]::Combine($linuxHome, "xdg-config")
    $env:XDG_DATA_HOME = [System.IO.Path]::Combine($linuxHome, "xdg-data")
    $linuxXdg = Get-SkillTrackerPlatformPaths -Platform Linux -UserHome $linuxHome
    Assert-Equal $linuxXdg.AppData $env:XDG_CONFIG_HOME "Linux XDG config root mismatch."
    Assert-Equal $linuxXdg.LocalAppData $env:XDG_DATA_HOME "Linux XDG data root mismatch."
} finally {
    $env:XDG_CONFIG_HOME = $previousXdgConfigHome
    $env:XDG_DATA_HOME = $previousXdgDataHome
}

$macHome = [System.IO.Path]::Combine([System.IO.Path]::GetPathRoot((Get-Location).Path), "Users", "tester")
$mac = Get-SkillTrackerPlatformPaths -Platform MacOS -UserHome $macHome
Assert-Equal $mac.AppData ([System.IO.Path]::Combine($macHome, "Library", "Application Support")) "macOS application support root mismatch."
Assert-Equal $mac.EditorWorkspaceStorageRoots[0] ([System.IO.Path]::Combine($macHome, "Library", "Application Support", "Code", "User", "workspaceStorage")) "macOS VS Code workspace storage mismatch."
if ($mac.CommonProgramRoots -notcontains "/Applications") { throw "macOS application roots must include /Applications." }

$windowsHome = "C:\Users\tester"
$windows = Get-SkillTrackerPlatformPaths -Platform Windows -UserHome $windowsHome -AppData "C:\Users\tester\AppData\Roaming" -LocalAppData "C:\Users\tester\AppData\Local" -ProgramFiles "C:\Program Files" -ProgramFilesX86 "C:\Program Files (x86)"
Assert-Equal $windows.EditorGlobalStorageRoots[0] "C:\Users\tester\AppData\Roaming\Code\User\globalStorage" "Windows VS Code storage mismatch."
if ($windows.CommonProgramRoots -notcontains "C:\Program Files") { throw "Windows program roots must include Program Files." }

Write-Host "Platform path contract passed."
