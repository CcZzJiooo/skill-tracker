<#
.SYNOPSIS
  Build a user-facing Windows portable release package for Skill Tracker.

.DESCRIPTION
  The generated ZIP contains only the runtime files needed for a local first-run
  collection and dashboard. Locally generated telemetry is intentionally excluded.
#>
param(
    [string]$Version = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Version)) {
    throw "Release version is required. Pass -Version, for example: -Version v0.2.1"
}
$SafeVersion = $Version -replace "[^A-Za-z0-9._-]", "-"

if (-not $OutputDir) { $OutputDir = Join-Path $RepoRoot "dist" }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$PackageName = "skill-tracker-$SafeVersion-windows-portable"
$StageRoot = Join-Path $OutputDir "_stage"
$StageDir = Join-Path $StageRoot $PackageName
$ZipPath = Join-Path $OutputDir "$PackageName.zip"
$ChecksumPath = Join-Path $OutputDir "SHA256SUMS.txt"
$VerifierPath = Join-Path $PSScriptRoot "verify-portable-release.ps1"

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
    "run.bat",
    "start-dashboard.ps1"
)
foreach ($file in $RootFiles) {
    $source = Join-Path $RepoRoot $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Missing required release file: $file"
    }
    Copy-Item -LiteralPath $source -Destination $StageDir -Force
}

New-Item -ItemType Directory -Path (Join-Path $StageDir "dashboard") -Force | Out-Null
foreach ($file in @("dashboard\index.html", "dashboard\demo_data.js")) {
    Copy-Item -LiteralPath (Join-Path $RepoRoot $file) -Destination (Join-Path $StageDir "dashboard") -Force
}

Copy-Item -LiteralPath (Join-Path $RepoRoot "docs") -Destination $StageDir -Recurse -Force
$InternalDocs = Join-Path $StageDir "docs\superpowers"
if (Test-Path -LiteralPath $InternalDocs) {
    Remove-Item -LiteralPath $InternalDocs -Recurse -Force
}

New-Item -ItemType Directory -Path (Join-Path $StageDir "scripts") -Force | Out-Null
foreach ($file in @("scripts\verify-collector.ps1", "scripts\verify-portable-release.ps1")) {
    Copy-Item -LiteralPath (Join-Path $RepoRoot $file) -Destination (Join-Path $StageDir "scripts") -Force
}

$StartHere = @"
Skill Tracker Windows Portable
==============================

Fastest path:
1. Download this ZIP from GitHub Releases and unzip it.
2. Double-click run.bat.
3. Wait for the visible launcher to finish reading local AI-agent logs. Your browser opens with the collected local dashboard data.

No installer, account, API key, or administrator permission is required.

The package does not include a VBS launcher or auto-create desktop shortcuts. To launch it later, double-click run.bat again.

If no supported local logs are found, the dashboard opens with an empty local scan report instead of fake activity. Demo data remains only a static fallback for viewing the interface without running the launcher.

Verify the downloaded ZIP with SHA256SUMS.txt before running it. For full instructions, open START_HERE.md.

Private generated files stay local and are not included in this release package:
- dashboard/skill_data.js
- dashboard/skill_log.js
- dashboard/skill_call_stats.json
- dashboard/skill_catalog.json
- dashboard/skill_catalog.js
- dashboard/tool_report.json
- dashboard/tool_report.js
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
if (@(Get-ChildItem -LiteralPath $StageDir -Recurse -File | Where-Object { $_.Extension -in @(".vbs", ".lnk") }).Count -gt 0) {
    throw "Release package must not contain VBS launchers or shortcut files."
}

Compress-Archive -Path $StageDir -DestinationPath $ZipPath -Force
$hash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$archiveName = [System.IO.Path]::GetFileName($ZipPath)
$archiveEntryPattern = '^[a-fA-F0-9]{64}\s+\*?' + [regex]::Escape($archiveName) + '$'
$existingChecksums = @()
if (Test-Path -LiteralPath $ChecksumPath -PathType Leaf) {
    $existingChecksums = @(Get-Content -LiteralPath $ChecksumPath -Encoding ASCII | Where-Object {
        $_ -and $_ -notmatch $archiveEntryPattern
    })
}
$updatedChecksums = @($existingChecksums + "$hash *$archiveName")
[System.IO.File]::WriteAllLines($ChecksumPath, $updatedChecksums, [System.Text.Encoding]::ASCII)

& powershell -NoProfile -ExecutionPolicy Bypass -File $VerifierPath -ZipPath $ZipPath -ChecksumPath $ChecksumPath
if ($LASTEXITCODE -ne 0) {
    throw "Portable release verification failed."
}

Remove-Item -LiteralPath $StageRoot -Recurse -Force

Write-Host "Created release package:"
Write-Host "  $ZipPath"
Write-Host "Checksum manifest:"
Write-Host "  $ChecksumPath"
