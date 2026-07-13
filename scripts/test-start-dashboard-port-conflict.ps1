param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-port-conflict-test-" + [guid]::NewGuid().ToString("N"))
$packageA = Join-Path $tempRoot "package-a"
$packageB = Join-Path $tempRoot "package-b"
$logDir = Join-Path $tempRoot "logs"
$fakeHome = Join-Path $tempRoot "home"
$port = Get-Random -Minimum 38001 -Maximum 42000

function Copy-PackageFiles {
    param([string]$DestinationRoot)

    foreach ($relativePath in @("collect.ps1", "start-dashboard.ps1", "dashboard/index.html", "dashboard/demo_data.js")) {
        $source = Join-Path $repoRoot $relativePath
        $destination = Join-Path $DestinationRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }

    $skillsRoot = Join-Path $DestinationRoot "fixtures\skills"
    $skillDir = Join-Path $skillsRoot "port-conflict-skill"
    New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $skillDir "SKILL.md"),
        "---`nname: port-conflict-skill`ndescription: Local port-conflict fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )

    $config = [ordered]@{
        skills_root = ""
        skills_roots = @($skillsRoot)
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

    $priorUserProfile = $env:USERPROFILE
    $priorHome = $env:HOME
    $priorAppData = $env:APPDATA
    $priorLocalAppData = $env:LOCALAPPDATA
    try {
        $env:USERPROFILE = $fakeHome
        $env:HOME = $fakeHome
        $env:APPDATA = Join-Path $fakeHome "AppData\Roaming"
        $env:LOCALAPPDATA = Join-Path $fakeHome "AppData\Local"

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
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
        $env:APPDATA = $priorAppData
        $env:LOCALAPPDATA = $priorLocalAppData
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
