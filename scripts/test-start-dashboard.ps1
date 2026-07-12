param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-launch-test-" + [guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $tempRoot "package"
$logDir = Join-Path $tempRoot "logs"
$port = Get-Random -Minimum 21000 -Maximum 25000

function Copy-RequiredFile {
    param([string]$RelativePath)

    $source = Join-Path $repoRoot $RelativePath
    $destination = Join-Path $packageRoot $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

try {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $logDir "launch-session.jsonl"),
        '{"type":"USER_INPUT","timestamp":"2026-07-12T12:00:00Z","text":"/launch-test-skill "}' + "`n",
        [System.Text.Encoding]::UTF8
    )

    foreach ($relativePath in @("collect.ps1", "start-dashboard.ps1", "dashboard/index.html", "dashboard/demo_data.js")) {
        Copy-RequiredFile -RelativePath $relativePath
    }
    $config = [ordered]@{
        skills_root = ""
        skills_roots = @()
        output_dir = "./dashboard"
        max_log_entries = 100
        dedup_window_minutes = 2
        custom_tools = @(
            [ordered]@{
                name = "Launch Test"
                path = $logDir
            }
        )
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $packageRoot "config.json"),
        ($config | ConvertTo-Json -Depth 5),
        [System.Text.Encoding]::UTF8
    )

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $packageRoot "start-dashboard.ps1") -Port $port -NoBrowser -NoWatch
    if ($LASTEXITCODE -ne 0) {
        throw "Launcher exited with code $LASTEXITCODE."
    }

    $skillDataPath = Join-Path $packageRoot "dashboard\skill_data.js"
    if (-not (Test-Path -LiteralPath $skillDataPath)) {
        throw "Launcher returned before first-run collection generated skill_data.js."
    }
    if ((Get-Content -LiteralPath $skillDataPath -Raw -Encoding UTF8) -notmatch 'launch-test-skill') {
        throw "Launcher returned before the initial local log was collected."
    }

    $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/index.html" -UseBasicParsing -TimeoutSec 5
    if ($response.Headers["X-Skill-Tracker-Server"] -ne "1") {
        throw "Launcher did not start the expected Skill Tracker server."
    }

    Write-Host "Dashboard first-run launcher test passed."
} finally {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($packageRoot) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
