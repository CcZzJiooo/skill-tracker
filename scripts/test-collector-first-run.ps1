param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $repoRoot "collect.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-collector-test-" + [guid]::NewGuid().ToString("N"))
$fakeHome = Join-Path $tempRoot "home"
$logDir = Join-Path $fakeHome "portable-test-logs"
$outputDir = Join-Path $tempRoot "dashboard"
$configPath = Join-Path $tempRoot "config.json"

function Assert-FileExists {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Expected generated file was not created: $Path"
    }
}

try {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $logDir "session.jsonl"),
        '{"type":"USER_INPUT","timestamp":"2026-07-12T12:00:00Z","text":"/portable-test-skill "}' + "`n",
        [System.Text.Encoding]::UTF8
    )

    $config = [ordered]@{
        skills_root = ""
        skills_roots = @()
        output_dir = $outputDir
        max_log_entries = 100
        dedup_window_minutes = 2
        custom_tools = @(
            [ordered]@{
                name = "Portable Test"
                path = $logDir
            }
        )
    }
    [System.IO.File]::WriteAllText(
        $configPath,
        ($config | ConvertTo-Json -Depth 5),
        [System.Text.Encoding]::UTF8
    )

    $priorUserProfile = $env:USERPROFILE
    $priorHome = $env:HOME
    try {
        $env:USERPROFILE = $fakeHome
        $env:HOME = $fakeHome
        & powershell -NoProfile -ExecutionPolicy Bypass -File $collector -ConfigFile $configPath -OutputDir $outputDir -RecentFiles 20 -RecentDays 45
        if ($LASTEXITCODE -ne 0) {
            throw "Collector exited with code $LASTEXITCODE for a first-run custom log source."
        }
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
    }

    foreach ($name in @("skill_data.js", "skill_log.js", "skill_catalog.js", "tool_report.js")) {
        Assert-FileExists -Path (Join-Path $outputDir $name)
    }

    $skillData = Get-Content -LiteralPath (Join-Path $outputDir "skill_data.js") -Raw -Encoding UTF8
    if ($skillData -notmatch 'portable-test-skill') {
        throw "Collector did not retain a skill discovered only in the user's local log."
    }

    $toolReport = Get-Content -LiteralPath (Join-Path $outputDir "tool_report.js") -Raw -Encoding UTF8
    if ($toolReport -notmatch 'Portable Test') {
        throw "Collector did not report the discovered local log source."
    }

    Write-Host "Collector first-run test passed."
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
