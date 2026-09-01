param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $repoRoot "collect.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-antigravity-layout-" + [guid]::NewGuid().ToString("N"))
$fakeHome = Join-Path $tempRoot "home"
$skillsRoot = Join-Path $fakeHome "skills"
$cliSkillDir = Join-Path $skillsRoot "antigravity-layout-skill"
$ideSkillDir = Join-Path $skillsRoot "antigravity-ide-layout-skill"
$cliBrainRoot = Join-Path $fakeHome ".gemini\antigravity\brain"
$ideBrainRoot = Join-Path $fakeHome ".gemini\antigravity-ide\brain"
$cliTranscriptDir = Join-Path $cliBrainRoot "00000000-0000-0000-0000-000000000001\.system_generated\logs"
$ideTranscriptDir = Join-Path $ideBrainRoot "00000000-0000-0000-0000-000000000002\.system_generated\logs"
$cliTranscriptPath = Join-Path $cliTranscriptDir "transcript.jsonl"
$ideTranscriptPath = Join-Path $ideTranscriptDir "transcript.jsonl"
$cliInstallDir = Join-Path $fakeHome "AppData\Local\Programs\Antigravity"
$cliInstallPath = Join-Path $cliInstallDir "Antigravity.exe"
$ideInstallDir = Join-Path $fakeHome "AppData\Local\Programs\Antigravity IDE"
$ideInstallPath = Join-Path $ideInstallDir "Antigravity IDE.exe"
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

function Get-SourceRow {
    param(
        [string]$ToolName,
        [string]$PathFragment
    )

    $report = Get-Content -LiteralPath (Join-Path $outputDir "tool_report.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($report.sources | Where-Object { $_.tool -eq $ToolName -and $_.path -like "*$PathFragment" })[0]
}

try {
    New-Item -ItemType Directory -Path $cliSkillDir,$ideSkillDir,$cliTranscriptDir,$ideTranscriptDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $cliSkillDir "SKILL.md"),
        "---`nname: antigravity-layout-skill`ndescription: Antigravity layout fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $ideSkillDir "SKILL.md"),
        "---`nname: antigravity-ide-layout-skill`ndescription: Antigravity IDE layout fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        $cliTranscriptPath,
        '{"step_index":0,"type":"USER_INPUT","created_at":"2026-08-05T01:00:00Z","content":"<USER_REQUEST>\n/antigravity-layout-skill\n</USER_REQUEST>"}' + "`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        $ideTranscriptPath,
        '{"step_index":0,"type":"USER_INPUT","created_at":"2026-08-05T01:01:00Z","content":"<USER_REQUEST>\n/antigravity-ide-layout-skill\n</USER_REQUEST>"}' + "`n",
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
        $cliRow = Get-SourceRow -ToolName "Antigravity" -PathFragment "\.gemini\antigravity\brain"
        $ideRow = Get-SourceRow -ToolName "AntigravityIDE" -PathFragment "\.gemini\antigravity-ide\brain"
        if (-not $cliRow -or -not $ideRow) {
            throw "Collector did not expose separate Antigravity and AntigravityIDE source rows."
        }
        $realAntigravityRunning = @(Get-Process -Name "Antigravity IDE","Antigravity" -ErrorAction SilentlyContinue).Count -gt 0
        if (-not $realAntigravityRunning) {
            foreach ($row in @($cliRow, $ideRow)) {
                if ($row.detected -or $row.files_scanned -ne 0 -or $row.status_reason -ne "tool_not_installed") {
                    throw "Antigravity source was scanned without an installation marker: $($row | ConvertTo-Json -Compress)"
                }
            }
        }

        New-Item -ItemType Directory -Path $cliInstallDir,$ideInstallDir -Force | Out-Null
        New-Item -ItemType File -Path $cliInstallPath,$ideInstallPath -Force | Out-Null
        Invoke-Collection | Out-Null
        $cliRow = Get-SourceRow -ToolName "Antigravity" -PathFragment "\.gemini\antigravity\brain"
        $ideRow = Get-SourceRow -ToolName "AntigravityIDE" -PathFragment "\.gemini\antigravity-ide\brain"
        foreach ($row in @($cliRow, $ideRow)) {
            if (-not $row.detected -or $row.files_scanned -lt 1 -or $row.install_reason -ne "install_marker") {
                throw "Separated Antigravity installation marker was not detected: $($row | ConvertTo-Json -Compress)"
            }
        }

        $log = @(Read-JsValue -Path (Join-Path $outputDir "skill_log.js") -Name "SKILL_LOG")
        if (-not (@($log | Where-Object { $_.tool -eq "Antigravity" -and $_.skill -eq "antigravity-layout-skill" }).Count)) {
            throw "Antigravity transcript skill call was not emitted under Antigravity."
        }
        if (-not (@($log | Where-Object { $_.tool -eq "AntigravityIDE" -and $_.skill -eq "antigravity-ide-layout-skill" }).Count)) {
            throw "Antigravity IDE transcript skill call was not emitted under AntigravityIDE."
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
