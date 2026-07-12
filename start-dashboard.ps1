param(
    [switch]$Server,
    [int]$Port = 17830,
    [switch]$NoBrowser,
    [switch]$NoWatch
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$DashboardDir = Join-Path $Root "dashboard"
$CollectorPath = Join-Path $Root "collect.ps1"
$ServerInstanceId = ([System.BitConverter]::ToString(
    [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes([System.IO.Path]::GetFullPath($Root).ToLowerInvariant())
    )
) -replace '-', '').ToLowerInvariant()
$RequiredGeneratedFiles = @(
    "skill_data.js",
    "skill_log.js",
    "skill_catalog.js",
    "tool_report.js"
)

function Test-SkillTrackerServer {
    param([int]$ListenPort)

    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$ListenPort/index.html" -UseBasicParsing -TimeoutSec 2
        return $response.StatusCode -eq 200 -and
            $response.Headers["X-Skill-Tracker-Server"] -eq "1" -and
            $response.Headers["X-Skill-Tracker-Instance"] -eq $ServerInstanceId
    } catch {
        return $false
    }
}

function Wait-SkillTrackerServer {
    param(
        [int]$ListenPort,
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (Test-SkillTrackerServer -ListenPort $ListenPort) { return $true }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)

    return $false
}

function Test-AnyHttpServer {
    param([int]$ListenPort)

    try {
        Invoke-WebRequest -Uri "http://127.0.0.1:$ListenPort/" -UseBasicParsing -TimeoutSec 2 | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Start-NoCacheServer {
    param([int]$ListenPort)

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://127.0.0.1:$ListenPort/")
    try {
        $listener.Start()
    } catch {
        throw "Cannot start Skill Tracker on http://127.0.0.1:$ListenPort/. Another application may already be using this port."
    }

    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            $requestPath = [Uri]::UnescapeDataString($context.Request.Url.AbsolutePath.TrimStart('/'))
            if ([string]::IsNullOrWhiteSpace($requestPath)) { $requestPath = "index.html" }
            $requestPath = $requestPath -replace '/', '\\'
            $fullPath = [System.IO.Path]::GetFullPath((Join-Path $DashboardDir $requestPath))
            $dashboardFullPath = [System.IO.Path]::GetFullPath($DashboardDir)

            if (-not $fullPath.StartsWith($dashboardFullPath, [System.StringComparison]::OrdinalIgnoreCase) -or
                -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                $context.Response.StatusCode = 404
                $bytes = [System.Text.Encoding]::UTF8.GetBytes("Not found")
            } else {
                $context.Response.StatusCode = 200
                $ext = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
                $context.Response.ContentType = switch ($ext) {
                    ".html" { "text/html; charset=utf-8" }
                    ".js"   { "application/javascript; charset=utf-8" }
                    ".json" { "application/json; charset=utf-8" }
                    ".css"  { "text/css; charset=utf-8" }
                    ".svg"  { "image/svg+xml" }
                    ".png"  { "image/png" }
                    default { "application/octet-stream" }
                }
                $bytes = [System.IO.File]::ReadAllBytes($fullPath)
            }

            $context.Response.Headers["X-Skill-Tracker-Server"] = "1"
            $context.Response.Headers["X-Skill-Tracker-Instance"] = $ServerInstanceId
            $context.Response.Headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
            $context.Response.Headers["Pragma"] = "no-cache"
            $context.Response.Headers["Expires"] = "0"
            $context.Response.ContentLength64 = $bytes.Length
            $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } catch {
            try { $context.Response.StatusCode = 500 } catch { }
        } finally {
            $context.Response.OutputStream.Close()
        }
    }
}

function Assert-GeneratedDashboardData {
    foreach ($file in $RequiredGeneratedFiles) {
        $path = Join-Path $DashboardDir $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Initial local collection did not generate $file."
        }
    }
}

function Test-CollectorWatcher {
    $pidPath = Join-Path $DashboardDir ".collector.pid"
    if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) { return $false }

    $watcherPidText = (Get-Content -LiteralPath $pidPath -Raw -ErrorAction SilentlyContinue).Trim()
    [int]$watcherPid = 0
    if (-not [int]::TryParse($watcherPidText, [ref]$watcherPid) -or $watcherPid -le 0) {
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
        return $false
    }

    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $watcherPid" -ErrorAction SilentlyContinue
    if (-not $process -or -not $process.CommandLine -or
        -not $process.CommandLine.Contains($CollectorPath) -or
        -not $process.CommandLine.Contains("-Watch")) {
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
        return $false
    }

    return $true
}

if ($Server) {
    Start-NoCacheServer -ListenPort $Port
    exit 0
}

if (-not (Test-Path -LiteralPath $DashboardDir -PathType Container)) {
    throw "Dashboard directory not found: $DashboardDir"
}
if (-not (Test-Path -LiteralPath $CollectorPath -PathType Leaf)) {
    throw "Collector script not found: $CollectorPath"
}

Write-Host "Reading local AI-agent logs..."
& $CollectorPath -RecentFiles 250 -RecentDays 45
if (-not $?) {
    throw "Initial local collection failed."
}
Assert-GeneratedDashboardData

if (-not (Test-SkillTrackerServer -ListenPort $Port)) {
    if (Test-AnyHttpServer -ListenPort $Port) {
        throw "Port $Port is already used by another local application. Close it or start Skill Tracker with a different -Port value."
    }

    Start-Process -FilePath "powershell" -WindowStyle Hidden -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`"",
        "-Server",
        "-Port", "$Port"
    )
    if (-not (Wait-SkillTrackerServer -ListenPort $Port -TimeoutSeconds 20)) {
        throw "Dashboard server did not become ready on http://127.0.0.1:$Port/."
    }
}

if (-not $NoWatch -and -not (Test-CollectorWatcher)) {
    Start-Process -FilePath "powershell" -WindowStyle Hidden -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$CollectorPath`"",
        "-Watch",
        "-RecentFiles", "250",
        "-RecentDays", "45"
    )
}

if (-not $NoBrowser) {
    Start-Process "http://127.0.0.1:$Port/index.html"
}
