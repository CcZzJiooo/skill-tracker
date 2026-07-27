param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-stale-watcher-test-" + [guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $tempRoot "package"
$logDir = Join-Path $tempRoot "logs"
$skillsRoot = Join-Path $tempRoot "skills"
$skillDir = Join-Path $skillsRoot "stale-watcher-skill"
$fakeHome = Join-Path $tempRoot "home"
$port = Get-Random -Minimum 26000 -Maximum 30000

function Copy-RequiredFile {
    param([string]$RelativePath)

    $source = Join-Path $repoRoot $RelativePath
    $destination = Join-Path $packageRoot $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

function Wait-ForFile {
    param([string]$Path, [int]$TimeoutSeconds = 20)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (Test-Path -LiteralPath $Path -PathType Leaf) { return $true }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $false
}

try {
    New-Item -ItemType Directory -Path $logDir,$skillDir,$fakeHome -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $skillDir "SKILL.md"),
        "---`nname: stale-watcher-skill`ndescription: Stale watcher fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $logDir "session.jsonl"),
        '{"type":"USER_INPUT","timestamp":"2026-07-27T12:00:00Z","text":"/stale-watcher-skill "}' + "`n",
        [System.Text.Encoding]::UTF8
    )

    foreach ($relativePath in @("collect.ps1", "start-dashboard.ps1", "dashboard/index.html", "dashboard/demo_data.js")) {
        Copy-RequiredFile -RelativePath $relativePath
    }
    $config = [ordered]@{
        skills_root = ""
        skills_roots = @($skillsRoot)
        output_dir = "./dashboard"
        max_log_entries = 50
        dedup_window_minutes = 2
        custom_tools = @([ordered]@{ name = "Stale Watcher Test"; path = $logDir })
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $packageRoot "config.json"),
        ($config | ConvertTo-Json -Depth 5),
        [System.Text.Encoding]::UTF8
    )

    $priorUserProfile = $env:USERPROFILE
    $priorHome = $env:HOME
    $priorAppData = $env:APPDATA
    $priorLocalAppData = $env:LOCALAPPDATA
    try {
        $env:USERPROFILE = $fakeHome
        $env:HOME = $fakeHome
        $env:APPDATA = Join-Path $fakeHome "AppData\Roaming"
        $env:LOCALAPPDATA = Join-Path $fakeHome "AppData\Local"

        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $packageRoot "start-dashboard.ps1") -Port $port -NoBrowser
        if ($LASTEXITCODE -ne 0) { throw "Initial launcher failed with code $LASTEXITCODE." }

        $pidPath = Join-Path $packageRoot "dashboard\.collector.pid"
        if (-not (Wait-ForFile -Path $pidPath)) { throw "Initial launcher did not start a watcher." }
        $oldPid = (Get-Content -LiteralPath $pidPath -Raw).Trim()

        $collectorPath = Join-Path $packageRoot "collect.ps1"
        (Get-Item -LiteralPath $collectorPath).LastWriteTime = (Get-Date).AddMinutes(1)

        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $packageRoot "start-dashboard.ps1") -Port $port -NoBrowser
        if ($LASTEXITCODE -ne 0) { throw "Launcher failed while replacing the stale watcher." }

        $deadline = (Get-Date).AddSeconds(20)
        do {
            $newPidText = Get-Content -LiteralPath $pidPath -Raw -ErrorAction SilentlyContinue
            $newPid = if ($newPidText) { $newPidText.Trim() } else { "" }
            if ($newPid -and $newPid -ne $oldPid) { break }
            Start-Sleep -Milliseconds 250
        } while ((Get-Date) -lt $deadline)
        if (-not $newPid -or $newPid -eq $oldPid) {
            throw "Launcher did not replace the watcher after the collector changed."
        }

        $newProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $newPid" -ErrorAction SilentlyContinue
        if (-not $newProcess -or $newProcess.CommandLine -notmatch '(?i)collect\.ps1.*-Watch') {
            throw "Replacement watcher PID does not identify the current collector watcher."
        }

        Write-Host "Dashboard stale-watcher replacement test passed."
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
        $env:APPDATA = $priorAppData
        $env:LOCALAPPDATA = $priorLocalAppData
    }
} finally {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($tempRoot) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
