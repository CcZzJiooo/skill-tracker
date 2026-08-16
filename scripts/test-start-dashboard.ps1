param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$runningOnWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
$powerShellExecutable = (Get-Process -Id $PID -ErrorAction Stop).Path
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-launch-test-" + [guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $tempRoot "package"
$logDir = Join-Path $tempRoot "logs"
$skillsRoot = Join-Path (Join-Path $packageRoot "fixtures") "skills"
$skillDir = Join-Path $skillsRoot "launch-test-skill"
$fakeHome = Join-Path $tempRoot "home"
$port = Get-Random -Minimum 21000 -Maximum 25000

function Copy-RequiredFile {
    param([string]$RelativePath)

    $source = Join-Path $repoRoot $RelativePath
    $destination = Join-Path $packageRoot $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

function Get-TestProcessIds {
    param([string]$RootPath)
    if ($runningOnWindows) {
        return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.Contains($RootPath) } |
            ForEach-Object { [int]$_.ProcessId })
    }
    $processIds = @()
    foreach ($line in @(& ps -eo pid=,command= 2>$null)) {
        if ($line -match '^\s*(\d+)\s+(.+)$' -and [int]$Matches[1] -ne $PID -and $Matches[2].Contains($RootPath)) {
            $processIds += [int]$Matches[1]
        }
    }
    return $processIds
}

try {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $logDir "launch-session.jsonl"),
        '{"type":"USER_INPUT","timestamp":"2026-07-12T12:00:00Z","text":"/launch-test-skill "}' + "`n",
        [System.Text.Encoding]::UTF8
    )

    foreach ($relativePath in @("collect.ps1", "start-dashboard.ps1", "dashboard/index.html", "dashboard/demo_data.js", "tools/platform-paths.psm1")) {
        Copy-RequiredFile -RelativePath $relativePath
    }
    New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $skillDir "SKILL.md"),
        "---`nname: launch-test-skill`ndescription: Local launcher fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    $config = [ordered]@{
        skills_root = ""
        skills_roots = @($skillsRoot)
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

    $priorUserProfile = $env:USERPROFILE
    $priorHome = $env:HOME
    $priorAppData = $env:APPDATA
    $priorLocalAppData = $env:LOCALAPPDATA
    try {
        $env:USERPROFILE = $fakeHome
        $env:HOME = $fakeHome
        $env:APPDATA = Join-Path $fakeHome "AppData\Roaming"
        $env:LOCALAPPDATA = Join-Path $fakeHome "AppData\Local"
        & $powerShellExecutable -NoLogo -NoProfile -File (Join-Path $packageRoot "start-dashboard.ps1") -Port $port -NoBrowser -NoWatch
        if ($LASTEXITCODE -ne 0) {
            throw "Launcher exited with code $LASTEXITCODE."
        }
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
        $env:APPDATA = $priorAppData
        $env:LOCALAPPDATA = $priorLocalAppData
    }

    $skillDataPath = Join-Path (Join-Path $packageRoot "dashboard") "skill_data.js"
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
    Get-TestProcessIds -RootPath $packageRoot |
        ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
