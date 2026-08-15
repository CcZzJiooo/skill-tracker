param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $repoRoot "collect.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-tool-lifecycle-" + [guid]::NewGuid().ToString("N"))
$fakeHome = Join-Path $tempRoot "home"
$skillsRoot = Join-Path $fakeHome "skills"
$skillDir = Join-Path $skillsRoot "lifecycle-skill"
$traeLogDir = Join-Path $fakeHome "AppData\Roaming\Trae\logs"
$traeInstallDir = Join-Path $fakeHome "AppData\Local\Programs\Trae"
$outputDir = Join-Path $tempRoot "dashboard"
$configPath = Join-Path $tempRoot "config.json"

function Write-Config {
    $config = [ordered]@{
        skills_root = ""
        skills_roots = @($skillsRoot)
        output_dir = $outputDir
        max_log_entries = 100
        dedup_window_minutes = 2
        custom_tools = @()
    }
    [System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)
}

function Invoke-Collection {
    $output = (& powershell -NoProfile -ExecutionPolicy Bypass -File $collector -ConfigFile $configPath -RecentFiles 0 -RecentDays 0 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "Collector failed: $output" }
    return $output
}

function Get-TraeRows {
    $report = Get-Content -LiteralPath (Join-Path $outputDir "tool_report.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($report.sources | Where-Object { $_.tool -eq "Trae" })
}

function Get-TraeLogRow {
    return @(Get-TraeRows | Where-Object { $_.path -like "*\AppData\Roaming\Trae\logs" })[0]
}

try {
    New-Item -ItemType Directory -Path $skillDir,$traeLogDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $skillDir "SKILL.md"),
        "---`nname: lifecycle-skill`ndescription: Tool lifecycle fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $traeLogDir "session.jsonl"),
        '{"type":"USER_INPUT","timestamp":"2026-08-05T01:00:00Z","text":"/lifecycle-skill "}' + "`n",
        [System.Text.Encoding]::UTF8
    )
    Write-Config

    $priorUserProfile = $env:USERPROFILE
    $priorHome = $env:HOME
    $priorAppData = $env:APPDATA
    $priorLocalAppData = $env:LOCALAPPDATA
    $priorProgramFiles = $env:ProgramFiles
    $priorProgramFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)", "Process")
    try {
        $env:USERPROFILE = $fakeHome
        $env:HOME = $fakeHome
        $env:APPDATA = Join-Path $fakeHome "AppData\Roaming"
        $env:LOCALAPPDATA = Join-Path $fakeHome "AppData\Local"
        $env:ProgramFiles = Join-Path $fakeHome "ProgramFiles"
        [Environment]::SetEnvironmentVariable("ProgramFiles(x86)", (Join-Path $fakeHome "ProgramFiles-x86"), "Process")

        Invoke-Collection | Out-Null
        $row = Get-TraeLogRow
        if ($row.detected -or $row.files_scanned -ne 0 -or $row.status_reason -ne "tool_not_installed") {
            throw "Removed Trae was scanned without an installation marker."
        }

        New-Item -ItemType Directory -Path $traeInstallDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $traeInstallDir "Trae.exe") -Force | Out-Null
        Invoke-Collection | Out-Null
        $row = Get-TraeLogRow
        if (-not $row.detected -or $row.files_scanned -lt 1 -or $row.install_reason -ne "install_marker") {
            throw "Installed Trae was not discovered from its executable marker: $($row | ConvertTo-Json -Compress)"
        }

        Remove-Item -LiteralPath $traeInstallDir -Recurse -Force
        Invoke-Collection | Out-Null
        $row = Get-TraeLogRow
        if ($row.detected -or $row.files_scanned -ne 0) {
            throw "Trae source remained active after its installation marker was removed: $($row | ConvertTo-Json -Compress)"
        }
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
        $env:APPDATA = $priorAppData
        $env:LOCALAPPDATA = $priorLocalAppData
        $env:ProgramFiles = $priorProgramFiles
        [Environment]::SetEnvironmentVariable("ProgramFiles(x86)", $priorProgramFilesX86, "Process")
    }

    Write-Host "Collector tool lifecycle test passed."
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
