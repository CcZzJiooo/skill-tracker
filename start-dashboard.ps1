param(
    [switch]$Server,
    [int]$Port = 17830,
    [switch]$NoBrowser,
    [switch]$NoWatch,
    [switch]$ForceScan
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$DashboardDir = Join-Path $Root "dashboard"
$CollectorPath = Join-Path $Root "collect.ps1"
$RunningOnWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
$RunningOnMacOS = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)
$PowerShellExecutable = try { (Get-Process -Id $PID -ErrorAction Stop).Path } catch { $null }
if (-not $PowerShellExecutable) {
    $PowerShellExecutable = if ($RunningOnWindows) { "powershell" } else { "pwsh" }
}
$ServerInstanceId = ([System.BitConverter]::ToString(
    [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes(
            ([System.IO.Path]::GetFullPath($Root).ToLowerInvariant()) + "|" +
            ((Get-Item -LiteralPath $PSCommandPath).LastWriteTimeUtc.Ticks.ToString())
        )
    )
) -replace '-', '').ToLowerInvariant()
$RequiredGeneratedFiles = @(
    "skill_data.js",
    "skill_log.js",
    "skill_catalog.js",
    "tool_report.js"
)
$CollectorTriggerPath = Join-Path $DashboardDir ".collector.trigger"

function Start-SkillTrackerPowerShell {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [string[]]$ScriptArguments = @()
    )

    $quotedScriptPath = '"' + $ScriptPath.Replace('"', '\"') + '"'
    $argumentList = @("-NoLogo", "-NoProfile")
    if ($RunningOnWindows) { $argumentList += @("-ExecutionPolicy", "Bypass") }
    $argumentList += @("-File", $quotedScriptPath)
    $argumentList += $ScriptArguments

    $startParams = @{
        FilePath = $PowerShellExecutable
        ArgumentList = $argumentList
        PassThru = $true
    }
    if ($RunningOnWindows) { $startParams.WindowStyle = "Hidden" }
    return Start-Process @startParams
}

function Get-ProcessCommandLine {
    param([int]$ProcessId)

    if ($RunningOnWindows) {
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
        if ($processInfo) { return [string]$processInfo.CommandLine }
        return ""
    }

    if (-not $RunningOnMacOS) {
        $procPath = "/proc/$ProcessId/cmdline"
        if (Test-Path -LiteralPath $procPath -PathType Leaf) {
            try {
                return ([System.IO.File]::ReadAllText($procPath) -replace "`0", " ").Trim()
            } catch { }
        }
    }

    try { return ((& ps -p $ProcessId -o command= 2>$null) | Out-String).Trim() } catch { return "" }
}

function Open-SkillTrackerBrowser {
    param([string]$Url)

    if ($RunningOnWindows) {
        Start-Process $Url | Out-Null
    } elseif ($RunningOnMacOS) {
        Start-Process -FilePath "open" -ArgumentList @($Url) | Out-Null
    } elseif (Get-Command xdg-open -ErrorAction SilentlyContinue) {
        Start-Process -FilePath "xdg-open" -ArgumentList @($Url) | Out-Null
    } else {
        Write-Host "Open this URL in your browser: $Url"
    }
}

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
            $rawPath = [Uri]::UnescapeDataString($context.Request.Url.AbsolutePath)
            if ($rawPath -eq "/api/sync" -or $rawPath.StartsWith("/api/shortcut/")) {
                $method = $context.Request.HttpMethod.ToUpperInvariant()
                $shortcutScript = Join-Path $Root "scripts\manage-shortcut.ps1"
                $bytes = @()

                if ($rawPath.StartsWith("/api/shortcut/") -and -not $RunningOnWindows) {
                    $context.Response.StatusCode = if ($rawPath -eq "/api/shortcut/status") { 200 } else { 501 }
                    $context.Response.ContentType = "application/json; charset=utf-8"
                    $resObj = [PSCustomObject]@{
                        supported = $false
                        success = $false
                        autoStart = $false
                        message = "Desktop shortcuts and login startup are available on Windows only."
                    }
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($resObj | ConvertTo-Json -Compress))
                } elseif ($rawPath -eq "/api/sync" -and ($method -eq "POST" -or $method -eq "GET")) {
                    $context.Response.StatusCode = 202
                    $context.Response.ContentType = "application/json; charset=utf-8"
                    $watcherRunning = Test-CollectorWatcher
                    if ($watcherRunning) {
                        [System.IO.File]::WriteAllText($CollectorTriggerPath, [DateTimeOffset]::UtcNow.ToString("o"), [System.Text.Encoding]::UTF8)
                        $mode = "watch_triggered"
                    } else {
                        $watcher = Start-CollectorWatcher
                        $mode = if ($watcher) { "watch_started" } else { "watch_unavailable" }
                    }
                    $resObj = [PSCustomObject]@{
                        success = [bool]($mode -ne "watch_unavailable")
                        accepted = [bool]($mode -ne "watch_unavailable")
                        mode = $mode
                        message = if ($mode -eq "watch_triggered") { "同步任务已加入后台收集队列" } elseif ($mode -eq "watch_started") { "已启动后台收集器" } else { "无法启动本地收集器" }
                    }
                    if (-not $resObj.success) { $context.Response.StatusCode = 503 }
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($resObj | ConvertTo-Json -Compress))
                } elseif ($rawPath -eq "/api/shortcut/status") {
                    $context.Response.StatusCode = 200
                    $context.Response.ContentType = "application/json; charset=utf-8"
                    $status = & $shortcutScript -Action GetStatus
                    $jsonStr = $status | ConvertTo-Json -Compress
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonStr)
                } elseif ($rawPath -eq "/api/shortcut/create-desktop" -and ($method -eq "POST" -or $method -eq "GET")) {
                    $context.Response.StatusCode = 200
                    $context.Response.ContentType = "application/json; charset=utf-8"
                    & $shortcutScript -Action CreateDesktopShortcut -CreateStartMenu
                    $resObj = [PSCustomObject]@{ success = $true; message = "桌面快捷方式创建成功！" }
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($resObj | ConvertTo-Json -Compress))
                } elseif ($rawPath -eq "/api/shortcut/toggle-autostart" -and ($method -eq "POST" -or $method -eq "GET")) {
                    $context.Response.StatusCode = 200
                    $context.Response.ContentType = "application/json; charset=utf-8"
                    $status = & $shortcutScript -Action GetStatus
                    if ($status.autoStart) {
                        & $shortcutScript -Action DisableAutoStart
                        $resObj = [PSCustomObject]@{ success = $true; autoStart = $false; message = "已关闭开机自启" }
                    } else {
                        & $shortcutScript -Action EnableAutoStart
                        $resObj = [PSCustomObject]@{ success = $true; autoStart = $true; message = "已开启开机自启" }
                    }
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($resObj | ConvertTo-Json -Compress))
                } else {
                    $context.Response.StatusCode = 404
                    $resObj = [PSCustomObject]@{ error = "API endpoint not found" }
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($resObj | ConvertTo-Json -Compress))
                }
            } else {
                $requestPath = $rawPath.TrimStart('/')
                if ([string]::IsNullOrWhiteSpace($requestPath)) { $requestPath = "index.html" }
                $dashboardFullPath = [System.IO.Path]::GetFullPath($DashboardDir)
                $platformRequestPath = $requestPath.Replace([char]'/', [System.IO.Path]::DirectorySeparatorChar)
                $fullPath = [System.IO.Path]::GetFullPath((Join-Path $dashboardFullPath $platformRequestPath))
                $dashboardPrefix = $dashboardFullPath.TrimEnd(
                    [System.IO.Path]::DirectorySeparatorChar,
                    [System.IO.Path]::AltDirectorySeparatorChar
                ) + [System.IO.Path]::DirectorySeparatorChar
                $pathComparison = if ($RunningOnWindows) {
                    [System.StringComparison]::OrdinalIgnoreCase
                } else {
                    [System.StringComparison]::Ordinal
                }

                if (-not $fullPath.StartsWith($dashboardPrefix, $pathComparison) -or
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

    $process = Get-Process -Id $watcherPid -ErrorAction SilentlyContinue
    $commandLine = if ($process) { Get-ProcessCommandLine -ProcessId $watcherPid } else { "" }
    $commandComparison = if ($RunningOnWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if ($env:SKILL_TRACKER_DEBUG) {
        Write-Host "Watcher check PID=$watcherPid process=$([bool]$process) collector='$CollectorPath' command='$commandLine'"
    }
    if (-not $process -or -not $commandLine -or
        $commandLine.IndexOf($CollectorPath, $commandComparison) -lt 0 -or
        $commandLine.IndexOf("-Watch", [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
        return $false
    }

    try {
        $collectorWriteUtc = (Get-Item -LiteralPath $CollectorPath -ErrorAction Stop).LastWriteTimeUtc
        $watcherStartUtc = ([datetime]$process.StartTime).ToUniversalTime()
        if ($watcherStartUtc -lt $collectorWriteUtc) {
            Stop-Process -Id $watcherPid -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $watcherPid -Timeout 5 -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
            return $false
        }
    } catch {
        # If process metadata is unavailable, ownership and the mutex remain the safety checks.
    }

    return $true
}

function Start-CollectorWatcher {
    if (Test-CollectorWatcher) { return $true }
    try {
        Start-SkillTrackerPowerShell -ScriptPath $CollectorPath -ScriptArguments @("-Watch") | Out-Null
        return $true
    } catch {
        return $false
    }
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

if (-not (Test-SkillTrackerServer -ListenPort $Port)) {
    if (Test-AnyHttpServer -ListenPort $Port) {
        throw "Port $Port is already used by another local server. Stop that server or choose another port."
    }

    Start-SkillTrackerPowerShell -ScriptPath $PSCommandPath -ScriptArguments @("-Server", "-Port", "$Port") | Out-Null
    if (-not (Wait-SkillTrackerServer -ListenPort $Port -TimeoutSeconds 20)) {
        throw "Dashboard server did not become ready on http://127.0.0.1:$Port/."
    }
}

if (-not $NoBrowser) {
    Open-SkillTrackerBrowser -Url "http://127.0.0.1:$Port/index.html"
}

# Auto-ensure desktop shortcut on initial launch
$shortcutScript = Join-Path $PSScriptRoot "scripts\manage-shortcut.ps1"
if ($RunningOnWindows -and (Test-Path -LiteralPath $shortcutScript)) {
    $desktopLnk = Join-Path ([Environment]::GetFolderPath("Desktop")) "技能追踪器.lnk"
    if (-not (Test-Path -LiteralPath $desktopLnk)) {
        & $PowerShellExecutable -NoLogo -NoProfile -ExecutionPolicy Bypass -File $shortcutScript -Action CreateDesktopShortcut -CreateStartMenu | Out-Null
        Write-Host "已自动在您的桌面创建【技能追踪器】快捷方式！"
    }
}

$hasGeneratedData = $true
foreach ($file in $RequiredGeneratedFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $DashboardDir $file) -PathType Leaf)) {
        $hasGeneratedData = $false
        break
    }
}

if ($NoWatch -and (-not $hasGeneratedData -or $ForceScan)) {
    Write-Host "Reading local AI-agent logs..."
    & $CollectorPath -ForceScan
    if (-not $?) {
        throw "Initial local collection failed."
    }
    Assert-GeneratedDashboardData
} elseif (-not $NoWatch) {
    if ($ForceScan -and (Test-CollectorWatcher)) {
        [System.IO.File]::WriteAllText($CollectorTriggerPath, [DateTimeOffset]::UtcNow.ToString("o"), [System.Text.Encoding]::UTF8)
    } elseif (-not (Test-CollectorWatcher)) {
        if (Start-CollectorWatcher) {
            if ($hasGeneratedData) {
                Write-Host "后台收集器已启动；本次启动不再阻塞等待历史日志扫描。"
            } else {
                Write-Host "首次本地收集已在后台启动，仪表盘生成后会自动刷新。"
            }
        } else {
            Write-Warning "Could not start the background collector watcher."
        }
    }
}
