param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-port-conflict-test-" + [guid]::NewGuid().ToString("N"))
$packageA = Join-Path $tempRoot "package-a"
$packageB = Join-Path $tempRoot "package-b"
$logDir = Join-Path $tempRoot "logs"
$port = Get-Random -Minimum 38001 -Maximum 42000

function Copy-PackageFiles {
    param([string]$DestinationRoot)

    foreach ($relativePath in @("collect.ps1", "start-dashboard.ps1", "dashboard/index.html", "dashboard/demo_data.js")) {
        $source = Join-Path $repoRoot $relativePath
        $destination = Join-Path $DestinationRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }

    $config = [ordered]@{
        skills_root = ""
        skills_roots = @()
        output_dir = "./dashboard"
        max_log_entries = 50
        dedup_window_minutes = 2
        custom_tools = @([ordered]@{ name = "Port Conflict Test"; path = $logDir })
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $DestinationRoot "config.json"),
        ($config | ConvertTo-Json -Depth 5),
        [System.Text.Encoding]::UTF8
    )
}

try {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $logDir "session.jsonl"),
        '{"type":"USER_INPUT","timestamp":"2026-07-12T12:00:00Z","text":"/port-conflict-skill "}' + "`n",
        [System.Text.Encoding]::UTF8
    )
    Copy-PackageFiles -DestinationRoot $packageA
    Copy-PackageFiles -DestinationRoot $packageB

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $packageA "start-dashboard.ps1") -Port $port -NoBrowser -NoWatch
    if ($LASTEXITCODE -ne 0) {
        throw "First package failed to start its local server."
    }

    $priorErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $secondOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $packageB "start-dashboard.ps1") -Port $port -NoBrowser -NoWatch 2>&1
        $secondExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $priorErrorActionPreference
    }
    if ($secondExitCode -eq 0) {
        throw "Second extracted package incorrectly reused the first package's server."
    }
    if (($secondOutput | Out-String) -notmatch "Port $port is already used") {
        throw "Second package did not report a clear port conflict."
    }

    Write-Host "Dashboard cross-package port conflict test passed."
} finally {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($tempRoot) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
