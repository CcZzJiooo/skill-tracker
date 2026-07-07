<#
.SYNOPSIS
  Build a user-facing Windows portable release package for Skill Tracker.

.DESCRIPTION
  The generated ZIP contains only files needed to run the local collector and
  dashboard. It intentionally excludes generated local telemetry files.
#>
param(
    [string]$Version = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Version) {
    try {
        $Version = (git -C $RepoRoot describe --tags --abbrev=0 2>$null).Trim()
    } catch {
        $Version = ""
    }
}
if (-not $Version) { $Version = "dev" }
$SafeVersion = $Version -replace "[^A-Za-z0-9._-]", "-"

if (-not $OutputDir) { $OutputDir = Join-Path $RepoRoot "dist" }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$PackageName = "skill-tracker-$SafeVersion-windows-portable"
$StageRoot = Join-Path $OutputDir "_stage"
$StageDir = Join-Path $StageRoot $PackageName
$ZipPath = Join-Path $OutputDir "$PackageName.zip"

if (Test-Path -LiteralPath $StageRoot) { Remove-Item -LiteralPath $StageRoot -Recurse -Force }
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
New-Item -ItemType Directory -Path $StageDir -Force | Out-Null

$RootFiles = @(
    "README.md",
    "LICENSE",
    "NOTICE",
    "SECURITY.md",
    "SUPPORT.md",
    "CONTRIBUTING.md",
    "CODE_OF_CONDUCT.md",
    "CITATION.cff",
    "START_HERE.md",
    "config.json",
    "collect.ps1",
    "run.bat"
)

foreach ($file in $RootFiles) {
    Copy-Item -LiteralPath (Join-Path $RepoRoot $file) -Destination $StageDir -Force
}

New-Item -ItemType Directory -Path (Join-Path $StageDir "dashboard") -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $RepoRoot "dashboard\index.html") -Destination (Join-Path $StageDir "dashboard") -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot "dashboard\demo_data.js") -Destination (Join-Path $StageDir "dashboard") -Force

Copy-Item -LiteralPath (Join-Path $RepoRoot "docs") -Destination $StageDir -Recurse -Force

$StartHere = @"
Skill Tracker Windows Portable
==============================

Fastest path:
1. Unzip this package.
2. Double-click run.bat.
3. Use the dashboard in your browser.

No server, installer, account, API key, or .exe is required.

If no local AI-agent logs are found, the dashboard still opens with demo data.

For full instructions, open START_HERE.md.

Private generated files stay local and are not included in this release package:
- dashboard/skill_data.js
- dashboard/skill_log.js
- dashboard/skill_call_stats.json
- dashboard/skill_catalog.json
- dashboard/skill_catalog.js
- dashboard/tool_report.json
- dashboard/tool_report.js

If Windows blocks the script, run this from PowerShell:
powershell -NoProfile -ExecutionPolicy Bypass -File .\collect.ps1
start .\dashboard\index.html
"@
[System.IO.File]::WriteAllText((Join-Path $StageDir "START_HERE.txt"), $StartHere, [System.Text.Encoding]::UTF8)

$ForbiddenFiles = @(
    "dashboard\skill_data.js",
    "dashboard\skill_log.js",
    "dashboard\skill_call_stats.json",
    "dashboard\skill_catalog.json",
    "dashboard\skill_catalog.js",
    "dashboard\tool_report.json",
    "dashboard\tool_report.js"
)
foreach ($file in $ForbiddenFiles) {
    if (Test-Path -LiteralPath (Join-Path $StageDir $file)) {
        throw "Release package unexpectedly contains private generated telemetry: $file"
    }
}

Compress-Archive -Path $StageDir -DestinationPath $ZipPath -Force
Remove-Item -LiteralPath $StageRoot -Recurse -Force

Write-Host "Created release package:"
Write-Host "  $ZipPath"
