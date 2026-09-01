param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$runningOnWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
$powerShellExecutable = (Get-Process -Id $PID -ErrorAction Stop).Path
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-stale-server-test-" + [guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $tempRoot "package"
$logDir = Join-Path $tempRoot "logs"
$skillsRoot = Join-Path $tempRoot "skills"
$skillDir = Join-Path $skillsRoot "stale-server-skill"
$fakeHome = Join-Path $tempRoot "home"
$port = Get-Random -Minimum 30001 -Maximum 34000

function Copy-RequiredFile {
    param([string]$RelativePath)

    $source = Join-Path $repoRoot $RelativePath
    $destination = Join-Path $packageRoot $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

function Get-PackageServerProcesses {
    if ($runningOnWindows) {
        $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{
                ProcessId = [int]$_.ProcessId
                CommandLine = [string]$_.CommandLine
            }
        })
    } else {
        $processes = @()
        foreach ($line in @(& ps -eo pid=,command= 2>$null)) {
            if ($line -match '^\s*(\d+)\s+(.+)$') {
                $processes += [pscustomobject]@{
                    ProcessId = [int]$Matches[1]
                    CommandLine = [string]$Matches[2]
                }
            }
        }
    }

    return @($processes | Where-Object {
        $_.ProcessId -ne $PID -and
        $_.CommandLine -and
        $_.CommandLine.Contains($packageRoot) -and
        $_.CommandLine -match '(?i)(^|\s)-Server(\s|$)' -and
        $_.CommandLine.Contains("-Port $port")
    })
}

try {
    New-Item -ItemType Directory -Path $logDir, $skillDir, $fakeHome -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $skillDir "SKILL.md"),
        "---`nname: stale-server-skill`ndescription: Stale server replacement fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $logDir "session.jsonl"),
        '{"type":"USER_INPUT","timestamp":"2026-09-01T04:00:00Z","text":"/stale-server-skill "}' + "`n",
        [System.Text.Encoding]::UTF8
    )

    foreach ($relativePath in @("collect.ps1", "start-dashboard.ps1", "dashboard/index.html", "dashboard/demo_data.js", "tools/platform-paths.psm1")) {
        Copy-RequiredFile -RelativePath $relativePath
    }
    $config = [ordered]@{
        skills_root = ""
        skills_roots = @($skillsRoot)
        output_dir = "./dashboard"
        max_log_entries = 50
        dedup_window_minutes = 2
        custom_tools = @([ordered]@{ name = "Stale Server Test"; path = $logDir })
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

        & $powerShellExecutable -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $packageRoot "start-dashboard.ps1") -Port $port -NoBrowser -NoWatch
        if ($LASTEXITCODE -ne 0) { throw "Initial launcher failed with code $LASTEXITCODE." }

        $oldServerProcesses = @(Get-PackageServerProcesses)
        if ($oldServerProcesses.Count -ne 1) {
            throw "Expected exactly one initial package server, found $($oldServerProcesses.Count)."
        }
        $oldServerPid = $oldServerProcesses[0].ProcessId

        $scriptInfo = Get-Item -LiteralPath (Join-Path $packageRoot "start-dashboard.ps1")
        $scriptInfo.LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(1)

        $priorErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            $secondOutput = & $powerShellExecutable -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $packageRoot "start-dashboard.ps1") -Port $port -NoBrowser -NoWatch 2>&1
            $secondExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $priorErrorActionPreference
        }
        if ($secondExitCode -ne 0) {
            throw "Launcher failed to replace the stale dashboard server. Output: $($secondOutput | Out-String)"
        }

        $newServerProcesses = @(Get-PackageServerProcesses)
        if ($newServerProcesses.Count -ne 1) {
            throw "Expected exactly one replacement package server, found $($newServerProcesses.Count)."
        }
        if ($newServerProcesses[0].ProcessId -eq $oldServerPid) {
            throw "Launcher reused the stale server instead of replacing it."
        }

        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/index.html" -UseBasicParsing -TimeoutSec 5
        if ($response.StatusCode -ne 200 -or $response.Headers["X-Skill-Tracker-Server"] -ne "1") {
            throw "Replacement server did not respond as a Skill Tracker server."
        }

        Write-Host "Dashboard stale-server replacement test passed."
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
        $env:APPDATA = $priorAppData
        $env:LOCALAPPDATA = $priorLocalAppData
    }
} finally {
    Get-PackageServerProcesses |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
