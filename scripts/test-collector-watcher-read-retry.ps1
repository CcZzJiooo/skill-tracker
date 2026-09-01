param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $repoRoot "collect.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-watcher-read-retry-" + [guid]::NewGuid().ToString("N"))
$fakeHome = Join-Path $tempRoot "home"
$skillsRoot = Join-Path $tempRoot "skills"
$initialSkillDir = Join-Path $skillsRoot "initial-retry-skill"
$retrySkillDir = Join-Path $skillsRoot "retry-after-lock-skill"
$logDir = Join-Path $tempRoot "logs"
$outputDir = Join-Path $tempRoot "dashboard"
$configPath = Join-Path $tempRoot "config.json"
$initialLogPath = Join-Path $logDir "initial.jsonl"
$retryLogPath = Join-Path $logDir "retry.jsonl"
$watcher = $null

function Wait-ForCondition {
    param(
        [scriptblock]$Condition,
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            if (& $Condition) { return $true }
        } catch { }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Get-Report {
    $path = Join-Path $outputDir "tool_report.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-Heartbeat {
    $path = Join-Path $outputDir ".collector-heartbeat.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

try {
    New-Item -ItemType Directory -Path $initialSkillDir,$retrySkillDir,$logDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $initialSkillDir "SKILL.md"),
        "---`nname: initial-retry-skill`ndescription: Initial watcher retry fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $retrySkillDir "SKILL.md"),
        "---`nname: retry-after-lock-skill`ndescription: Skill discovered after a transient file lock.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        $initialLogPath,
        '{"type":"USER_INPUT","timestamp":"2026-08-07T01:00:00Z","text":"/initial-retry-skill "}' + "`n",
        [System.Text.Encoding]::UTF8
    )
    $config = [ordered]@{
        skills_root = ""
        skills_roots = @($skillsRoot)
        output_dir = $outputDir
        max_log_entries = 100
        dedup_window_minutes = 2
        custom_tools = @([ordered]@{ name = "Read Retry Test"; path = $logDir })
    }
    [System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)

    $priorUserProfile = $env:USERPROFILE
    $priorHome = $env:HOME
    $priorAppData = $env:APPDATA
    $priorLocalAppData = $env:LOCALAPPDATA
    try {
        $env:USERPROFILE = $fakeHome
        $env:HOME = $fakeHome
        $env:APPDATA = Join-Path $fakeHome "AppData\Roaming"
        $env:LOCALAPPDATA = Join-Path $fakeHome "AppData\Local"
        $watcher = Start-Process -FilePath "powershell" -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$collector`"",
            "-ConfigFile", "`"$configPath`"", "-Watch", "-RecentFiles", "20"
        ) -PassThru -WindowStyle Hidden

        $initialLogOutput = Join-Path $outputDir "skill_log.js"
        if (-not (Wait-ForCondition { Test-Path -LiteralPath $initialLogOutput -PathType Leaf })) {
            throw "Watcher did not generate the initial output before the retry fixture."
        }

        $lockStream = $null
        try {
            $lockStream = [System.IO.FileStream]::new(
                $retryLogPath,
                [System.IO.FileMode]::Create,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(
                '{"type":"USER_INPUT","timestamp":"2026-08-07T02:00:00Z","text":"/retry-after-lock-skill "}' + "`n"
            )
            $lockStream.Write($bytes, 0, $bytes.Length)
            $lockStream.Flush($true)

            if (-not (Wait-ForCondition {
                $report = Get-Report
                $report -and [int]$report.summary.read_error_count -gt 0
            })) {
                throw "Watcher did not record the transient read failure while the log was locked."
            }
            if (-not (Wait-ForCondition {
                $heartbeat = Get-Heartbeat
                $heartbeat -and $heartbeat.status -eq "degraded" -and $heartbeat.last_error
            })) {
                throw "Watcher did not expose a degraded heartbeat for the transient read failure."
            }
        } finally {
            if ($lockStream) { $lockStream.Dispose() }
        }

        if (-not (Wait-ForCondition {
            if (-not (Test-Path -LiteralPath $initialLogOutput -PathType Leaf)) { return $false }
            (Get-Content -LiteralPath $initialLogOutput -Raw -Encoding UTF8).Contains("retry-after-lock-skill")
        })) {
            throw "Watcher did not retry the unchanged log after the transient lock was released."
        }
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
        $env:APPDATA = $priorAppData
        $env:LOCALAPPDATA = $priorLocalAppData
    }

    Write-Host "Collector watcher read-retry test passed."
} finally {
    if ($watcher -and -not $watcher.HasExited) {
        Stop-Process -Id $watcher.Id -Force -ErrorAction SilentlyContinue
    }
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($tempRoot) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
