param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $repoRoot "collect.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-empty-test-" + [guid]::NewGuid().ToString("N"))
$fakeHome = Join-Path $tempRoot "home"
$emptySkillsRoot = Join-Path $tempRoot "empty-skills"
$outputDir = Join-Path $tempRoot "dashboard"
$configPath = Join-Path $tempRoot "config.json"

try {
    New-Item -ItemType Directory -Path $fakeHome -Force | Out-Null
    New-Item -ItemType Directory -Path $emptySkillsRoot -Force | Out-Null
    $config = [ordered]@{
        skills_root = $emptySkillsRoot
        skills_roots = @()
        output_dir = $outputDir
        max_log_entries = 100
        dedup_window_minutes = 2
        custom_tools = @()
    }
    [System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 4), [System.Text.Encoding]::UTF8)

    $priorUserProfile = $env:USERPROFILE
    $priorHome = $env:HOME
    try {
        $env:USERPROFILE = $fakeHome
        $env:HOME = $fakeHome
        & powershell -NoProfile -ExecutionPolicy Bypass -File $collector -ConfigFile $configPath -OutputDir $outputDir -RecentFiles 20 -RecentDays 45
        if ($LASTEXITCODE -ne 0) {
            throw "Collector exited with code $LASTEXITCODE when no local logs were available."
        }
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
    }

    $expectedAssignments = @{
        "skill_data.js" = "var SKILL_DATA = [];"
        "skill_log.js" = "var SKILL_LOG = [];"
        "skill_catalog.js" = "var SKILL_CATALOG = [];"
    }
    foreach ($entry in $expectedAssignments.GetEnumerator()) {
        $path = Join-Path $outputDir $entry.Key
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Collector did not generate $($entry.Key) for an empty local scan."
        }
        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ($content -notmatch [regex]::Escape($entry.Value)) {
            throw "Collector did not emit a valid empty assignment in $($entry.Key)."
        }
        & node --check $path
        if ($LASTEXITCODE -ne 0) {
            throw "$($entry.Key) is not valid JavaScript."
        }
    }

    $catalogJsonPath = Join-Path $outputDir "skill_catalog.json"
    $catalogJson = Get-Content -LiteralPath $catalogJsonPath -Raw -Encoding UTF8
    if ($catalogJson.Trim() -ne "[]") {
        throw "Collector did not emit an empty JSON array in skill_catalog.json."
    }
    & node -e 'const value = JSON.parse(process.argv[1]); if (!Array.isArray(value) || value.length !== 0) process.exit(1);' $catalogJson
    if ($LASTEXITCODE -ne 0) {
        throw "skill_catalog.json does not parse as an empty array."
    }

    Write-Host "Collector empty first-run test passed."
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
