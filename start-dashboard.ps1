param(
    [switch]$Server,
    [int]$Port = 17830
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$DashboardDir = Join-Path $Root "dashboard"
$ProjectPattern = [regex]::Escape($Root)

function Stop-ExistingProjectProcess {
    param([string]$Pattern)

    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object {
            $_.ProcessId -ne $PID -and
            $_.CommandLine -match $ProjectPattern -and
            $_.CommandLine -match $Pattern
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}

function Wait-DashboardServer {
    param(
        [int]$ListenPort,
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$ListenPort/index.html" -UseBasicParsing -TimeoutSec 2
            if ($response.StatusCode -eq 200) { return $true }
        } catch { }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)

    return $false
}

function Start-NoCacheServer {
    param([int]$ListenPort)

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://127.0.0.1:$ListenPort/")
    $listener.Start()

    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            $requestPath = [Uri]::UnescapeDataString($context.Request.Url.AbsolutePath.TrimStart('/'))
            if ([string]::IsNullOrWhiteSpace($requestPath)) { $requestPath = "index.html" }
            $requestPath = $requestPath -replace '/', '\'
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

if ($Server) {
    Start-NoCacheServer -ListenPort $Port
    exit 0
}

if (-not (Test-Path -LiteralPath $DashboardDir -PathType Container)) {
    throw "Dashboard directory not found: $DashboardDir"
}

Stop-ExistingProjectProcess -Pattern "collect\.ps1"
Stop-ExistingProjectProcess -Pattern "start-dashboard\.ps1.*-Server"

Start-Process -FilePath "powershell" -WindowStyle Hidden -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$PSCommandPath`"",
    "-Server",
    "-Port", "$Port"
)

if (-not (Wait-DashboardServer -ListenPort $Port -TimeoutSeconds 20)) {
    throw "Dashboard server did not become ready on http://127.0.0.1:$Port/"
}

Start-Process -FilePath "powershell" -WindowStyle Hidden -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$(Join-Path $Root 'collect.ps1')`"",
    "-Watch",
    "-RecentFiles", "250",
    "-RecentDays", "45"
)

Start-Process "http://127.0.0.1:$Port/index.html"
