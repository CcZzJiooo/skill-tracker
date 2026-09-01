param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-configured-output-" + [guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $tempRoot "package"
$fakeHome = Join-Path $tempRoot "home"
$skillsRoot = Join-Path $tempRoot "skills"
$skillDir = Join-Path $skillsRoot "configured-output-skill"
$logDir = Join-Path $tempRoot "logs"
$outputDir = Join-Path $tempRoot "runtime-data"
$configPath = Join-Path $tempRoot "config.json"
$port = Get-Random -Minimum 30000 -Maximum 34000

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
        "---`nname: configured-output-skill`ndescription: Relative configuration fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $logDir "session.jsonl"),
        '{"type":"USER_INPUT","timestamp":"2026-08-06T04:00:00Z","text":"/configured-output-skill "}' + "`n",
        [System.Text.Encoding]::UTF8
    )

    foreach ($relativePath in @("collect.ps1", "start-dashboard.ps1", "dashboard/index.html", "dashboard/demo_data.js", "tools/platform-paths.psm1")) {
        Copy-RequiredFile -RelativePath $relativePath
    }
    $config = [ordered]@{
        skills_root = ""
        skills_roots = @("./skills")
        output_dir = "./runtime-data"
        max_log_entries = 100
        dedup_window_minutes = 2
        custom_tools = @([ordered]@{ name = "Configured Output"; path = "./logs" })
    }
    [System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 6), [System.Text.Encoding]::UTF8)

    $priorUserProfile = $env:USERPROFILE
    $priorHome = $env:HOME
    $priorAppData = $env:APPDATA
    $priorLocalAppData = $env:LOCALAPPDATA
    try {
        $env:USERPROFILE = $fakeHome
        $env:HOME = $fakeHome
        $env:APPDATA = Join-Path $fakeHome "AppData\Roaming"
        $env:LOCALAPPDATA = Join-Path $fakeHome "AppData\Local"

        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $packageRoot "start-dashboard.ps1") -ConfigFile $configPath -Port $port -NoBrowser
        if ($LASTEXITCODE -ne 0) { throw "Configured-output launcher failed with code $LASTEXITCODE." }
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
        $env:APPDATA = $priorAppData
        $env:LOCALAPPDATA = $priorLocalAppData
    }

    $logOutput = Join-Path $outputDir "skill_log.js"
    if (-not (Wait-ForText -Path $logOutput -Text 'configured-output-skill')) {
        throw "Collector did not write generated data to the configured output directory."
    }
    if (Test-Path -LiteralPath (Join-Path $packageRoot "dashboard\skill_log.js")) {
        throw "Collector unexpectedly wrote telemetry into the static dashboard directory."
    }

    $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/skill_log.js" -UseBasicParsing -TimeoutSec 10
    if ($response.StatusCode -ne 200 -or $response.Content -notmatch 'configured-output-skill') {
        throw "Dashboard server did not serve data from the configured output directory."
    }
    $status = Invoke-WebRequest -Uri "http://127.0.0.1:$port/api/watcher-status" -UseBasicParsing -TimeoutSec 10 | Select-Object -ExpandProperty Content | ConvertFrom-Json
    if (-not $status.running -or $status.output_dir -ne $outputDir) {
        throw "Watcher status did not confirm the configured output directory: $($status | ConvertTo-Json -Compress)"
    }

    Write-Host "Start-dashboard configured-output test passed."
} finally {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($packageRoot) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
