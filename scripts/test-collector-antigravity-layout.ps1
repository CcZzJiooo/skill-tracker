param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $repoRoot "collect.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-antigravity-layout-" + [guid]::NewGuid().ToString("N"))
$fakeHome = Join-Path $tempRoot "home"
$skillsRoot = Join-Path $fakeHome "skills"
$skillDir = Join-Path $skillsRoot "antigravity-layout-skill"
$brainRoot = Join-Path $fakeHome ".gemini\antigravity-ide\brain"
$transcriptDir = Join-Path $brainRoot "00000000-0000-0000-0000-000000000001\.system_generated\logs"
$transcriptPath = Join-Path $transcriptDir "transcript.jsonl"
$installDir = Join-Path $fakeHome "AppData\Local\Programs\Antigravity IDE"
$installPath = Join-Path $installDir "Antigravity IDE.exe"
$outputDir = Join-Path $tempRoot "dashboard"
$configPath = Join-Path $tempRoot "config.json"

function Invoke-Collection {
    $output = (& powershell -NoProfile -ExecutionPolicy Bypass -File $collector -ConfigFile $configPath -RecentFiles 0 -RecentDays 0 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "Collector failed: $output" }
    return $output
}

function Read-JsValue {
    param([string]$Path, [string]$Name)
    $prefix = "var $Name = "
    $line = Get-Content -LiteralPath $Path -Encoding UTF8 | Where-Object { $_.StartsWith($prefix) } | Select-Object -First 1
    if (-not $line) { throw "Missing $Name assignment in $Path" }
    $json = $line.Substring($prefix.Length).Trim()
    if ($json.EndsWith(";")) { $json = $json.Substring(0, $json.Length - 1) }
    return ($json | ConvertFrom-Json)
}

function Get-AntigravitySourceRow {
    $report = Get-Content -LiteralPath (Join-Path $outputDir "tool_report.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($report.sources | Where-Object { $_.tool -eq "Antigravity" -and $_.path -like "*\.gemini\antigravity-ide\brain" })[0]
}

try {
    New-Item -ItemType Directory -Path $skillDir,$transcriptDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $skillDir "SKILL.md"),
        "---`nname: antigravity-layout-skill`ndescription: Antigravity layout fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        $transcriptPath,
        '{"step_index":0,"type":"USER_INPUT","created_at":"2026-08-05T01:00:00Z","content":"<USER_REQUEST>\n/antigravity-layout-skill\n</USER_REQUEST>"}' + "`n",
        [System.Text.Encoding]::UTF8
    )
    $config = [ordered]@{
        skills_root = ""
        skills_roots = @($skillsRoot)
        output_dir = $outputDir
        max_log_entries = 100
        dedup_window_minutes = 2
        custom_tools = @()
    }
    [System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)

    $priorUserProfile = $env:USERPROFILE
    $priorHome = $env:HOME
    $priorAppData = $env:APPDATA
    $priorLocalAppData = $env:LOCALAPPDATA
    $priorProgramFiles = $env:ProgramFiles
    $priorPath = $env:PATH
    $priorProgramFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)", "Process")
    try {
        $env:USERPROFILE = $fakeHome
        $env:HOME = $fakeHome
        $env:APPDATA = Join-Path $fakeHome "AppData\Roaming"
        $env:LOCALAPPDATA = Join-Path $fakeHome "AppData\Local"
        $env:ProgramFiles = Join-Path $fakeHome "ProgramFiles"
        $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
        [Environment]::SetEnvironmentVariable("ProgramFiles(x86)", (Join-Path $fakeHome "ProgramFiles-x86"), "Process")

        Invoke-Collection | Out-Null
        $row = Get-AntigravitySourceRow
        if ($row.detected -or $row.files_scanned -ne 0 -or $row.status_reason -ne "tool_not_installed") {
            throw "Antigravity logs were scanned without an installation marker: $($row | ConvertTo-Json -Compress)"
        }

        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        New-Item -ItemType File -Path $installPath -Force | Out-Null
        Invoke-Collection | Out-Null
        $row = Get-AntigravitySourceRow
        if (-not $row.detected -or $row.files_scanned -lt 1 -or $row.install_reason -ne "install_marker") {
            throw "Antigravity IDE's spaced install path was not detected: $($row | ConvertTo-Json -Compress)"
        }

        $log = @(Read-JsValue -Path (Join-Path $outputDir "skill_log.js") -Name "SKILL_LOG")
        if (-not (@($log | Where-Object { $_.tool -eq "Antigravity" -and $_.skill -eq "antigravity-layout-skill" }).Count)) {
            throw "Antigravity transcript skill call was not emitted."
        }
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
        $env:APPDATA = $priorAppData
        $env:LOCALAPPDATA = $priorLocalAppData
        $env:ProgramFiles = $priorProgramFiles
        $env:PATH = $priorPath
        [Environment]::SetEnvironmentVariable("ProgramFiles(x86)", $priorProgramFilesX86, "Process")
    }

    Write-Host "Collector Antigravity install-layout test passed."
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
