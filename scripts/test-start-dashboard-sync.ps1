param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-sync-test-" + [guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $tempRoot "package"
$fakeHome = Join-Path $tempRoot "home"
$skillsRoot = Join-Path $fakeHome "skills"
$skillDir = Join-Path $skillsRoot "sync-skill"
$logDir = Join-Path $fakeHome "sync-logs"
$port = Get-Random -Minimum 25000 -Maximum 29000

function Copy-RequiredFile {
    param([string]$RelativePath)
    $source = Join-Path $repoRoot $RelativePath
    $destination = Join-Path $packageRoot $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

function Wait-ForText {
    param([string]$Path, [string]$Text, [int]$TimeoutSeconds = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            try {
                if ((Get-Content -LiteralPath $Path -Raw -Encoding UTF8).Contains($Text)) { return $true }
            } catch { }
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $false
}

try {
    New-Item -ItemType Directory -Path $skillDir,$logDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $skillDir "SKILL.md"),
        "---`nname: sync-skill`ndescription: Sync endpoint fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    $logPath = Join-Path $logDir "session.jsonl"
    [System.IO.File]::WriteAllText(
        $logPath,
        '{"type":"USER_INPUT","timestamp":"2026-08-05T04:00:00Z","text":"/sync-skill "}' + "`n",
        [System.Text.Encoding]::UTF8
    )
    foreach ($relativePath in @("collect.ps1", "start-dashboard.ps1", "dashboard/index.html", "dashboard/demo_data.js")) {
        Copy-RequiredFile -RelativePath $relativePath
    }
    $config = [ordered]@{
        skills_root = ""
        skills_roots = @($skillsRoot)
        output_dir = "./dashboard"
        max_log_entries = 100
        dedup_window_minutes = 2
        custom_tools = @([ordered]@{ name = "Sync Fixture"; path = $logDir })
    }
    [System.IO.File]::WriteAllText((Join-Path $packageRoot "config.json"), ($config | ConvertTo-Json -Depth 6), [System.Text.Encoding]::UTF8)

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
        if ($LASTEXITCODE -ne 0) { throw "Launcher failed to start." }
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
        $env:APPDATA = $priorAppData
        $env:LOCALAPPDATA = $priorLocalAppData
    }

    $logOutput = Join-Path $packageRoot "dashboard\skill_log.js"
    if (-not (Wait-ForText -Path $logOutput -Text '"time":"2026-08-05T04:00:00Z"')) {
        throw "Background watcher did not produce the initial dashboard data."
    }

    [System.IO.File]::AppendAllText($logPath, '{"type":"USER_INPUT","timestamp":"2026-08-05T05:00:00Z","text":"/sync-skill "}' + "`n", [System.Text.Encoding]::UTF8)
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/api/sync" -Method Post -UseBasicParsing -TimeoutSec 10
    if ($response.StatusCode -ne 202) { throw "Sync endpoint returned HTTP $($response.StatusCode), expected 202." }
    $payload = $response.Content | ConvertFrom-Json
    if (-not $payload.accepted) { throw "Sync endpoint did not accept the background sync request." }
    if (-not (Wait-ForText -Path $logOutput -Text '"time":"2026-08-05T05:00:00Z"')) {
        throw "Accepted sync request did not refresh the latest local log data."
    }

    Write-Host "Start-dashboard sync API test passed."
} finally {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($packageRoot) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
