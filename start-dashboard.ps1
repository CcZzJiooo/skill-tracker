param(
    [switch]$Server,
    [int]$Port = 17830,
    [switch]$NoBrowser,
    [switch]$NoWatch,
    [switch]$ForceScan,
    [string]$ConfigFile = "$PSScriptRoot/config.json"
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$DashboardDir = Join-Path $Root "dashboard"
$CollectorPath = Join-Path $Root "collect.ps1"
$resolvedConfigFile = if ([System.IO.Path]::IsPathRooted($ConfigFile)) {
    [System.IO.Path]::GetFullPath($ConfigFile)
} else {
    [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $ConfigFile))
}
if (-not (Test-Path -LiteralPath $resolvedConfigFile -PathType Leaf) -and -not [System.IO.Path]::IsPathRooted($ConfigFile)) {
    $packageConfig = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $ConfigFile))
    if (Test-Path -LiteralPath $packageConfig -PathType Leaf) { $resolvedConfigFile = $packageConfig }
}
$configBaseDir = Split-Path -Parent $resolvedConfigFile
$configuredOutputDir = "./dashboard"
if (Test-Path -LiteralPath $resolvedConfigFile -PathType Leaf) {
    try {
        $launcherConfig = Get-Content -LiteralPath $resolvedConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($launcherConfig.output_dir) { $configuredOutputDir = [string]$launcherConfig.output_dir }
    } catch {
        Write-Warning "Could not parse config.json for the dashboard output path; using ./dashboard."
    }
}
$configuredOutputDir = [Environment]::ExpandEnvironmentVariables($configuredOutputDir).Trim()
$configuredHome = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { "" }
if ($configuredHome -and $configuredOutputDir -match '^~([\\/]|$)') {
    $configuredOutputDir = $configuredHome + $configuredOutputDir.Substring(1)
}
$DataDir = if ([System.IO.Path]::IsPathRooted($configuredOutputDir)) {
    [System.IO.Path]::GetFullPath($configuredOutputDir)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $configBaseDir $configuredOutputDir))
}
New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
$HeartbeatMaxAgeSeconds = 90
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
$GeneratedDataFiles = @(
    "skill_data.js",
    "skill_log.js",
    "skill_call_stats.json",
    "skill_catalog.json",
    "skill_catalog.js",
    "tool_report.json",
    "tool_report.js"
)
$CollectorTriggerPath = Join-Path $DataDir ".collector.trigger"

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
    foreach ($argument in $ScriptArguments) {
        $value = [string]$argument
        if ($value -match '[\s"]') {
            $argumentList += '"' + $value.Replace('"', '\"') + '"'
        } else {
            $argumentList += $value
        }
    }

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

function Get-ManagedSkillTrackerServerProcesses {
    param([int]$ListenPort)

    if ($RunningOnWindows) {
        $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    } else {
        $processes = @()
        foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
            $processes += [pscustomobject]@{
                ProcessId = [int]$process.Id
                CommandLine = Get-ProcessCommandLine -ProcessId $process.Id
            }
        }
    }

    $scriptPath = [System.IO.Path]::GetFullPath($PSCommandPath)
    $portPattern = '(?i)(^|\s)-Port\s+["'']?' + [regex]::Escape($ListenPort.ToString()) + '["'']?(?:\s|$)'
    return @($processes | Where-Object {
        $commandLine = [string]$_.CommandLine
        $_.ProcessId -ne $PID -and
        $commandLine -and
        $commandLine.IndexOf($scriptPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
        $commandLine -match '(?i)(^|\s)-Server(?:\s|$)' -and
        $commandLine -match $portPattern
    })
}

function Stop-ManagedSkillTrackerServers {
    param([int]$ListenPort)

    $managedProcesses = @(Get-ManagedSkillTrackerServerProcesses -ListenPort $ListenPort)
    if ($managedProcesses.Count -eq 0) { return $false }

    foreach ($process in $managedProcesses) {
        if ([int]$process.ProcessId -ne $PID) {
            Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction SilentlyContinue
        }
    }

    $deadline = (Get-Date).AddSeconds(10)
    do {
        if (@(Get-ManagedSkillTrackerServerProcesses -ListenPort $ListenPort).Count -eq 0) {
            return $true
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    return $false
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
            if ($rawPath -eq "/api/sync" -or $rawPath -eq "/api/watcher-status" -or $rawPath.StartsWith("/api/shortcut/")) {
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
                } elseif ($rawPath -eq "/api/watcher-status" -and $method -eq "GET") {
                    $context.Response.StatusCode = 200
                    $context.Response.ContentType = "application/json; charset=utf-8"
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-CollectorWatcherStatus | ConvertTo-Json -Compress))
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
                $contentRoot = if ($GeneratedDataFiles -contains $requestPath) { $DataDir } else { $DashboardDir }
                $dashboardFullPath = [System.IO.Path]::GetFullPath($contentRoot)
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
        $path = Join-Path $DataDir $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Initial local collection did not generate $file."
        }
    }
}

function Read-CollectorHeartbeat {
    $heartbeatPath = Join-Path $DataDir ".collector-heartbeat.json"
    if (-not (Test-Path -LiteralPath $heartbeatPath -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $heartbeatPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-CollectorWatcherStatus {
    $pidPath = Join-Path $DataDir ".collector.pid"
    $heartbeat = Read-CollectorHeartbeat
    $pidText = if (Test-Path -LiteralPath $pidPath -PathType Leaf) {
        (Get-Content -LiteralPath $pidPath -Raw -ErrorAction SilentlyContinue).Trim()
    } else { "" }
    [int]$watcherPid = 0
    $pidValid = [int]::TryParse($pidText, [ref]$watcherPid) -and $watcherPid -gt 0
    $process = if ($pidValid) { Get-Process -Id $watcherPid -ErrorAction SilentlyContinue } else { $null }
    $commandLine = if ($process) { Get-ProcessCommandLine -ProcessId $watcherPid } else { "" }
    $commandComparison = if ($RunningOnWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $processMatches = [bool]($process -and $commandLine -and
        $commandLine.IndexOf($CollectorPath, $commandComparison) -ge 0 -and
        $commandLine.IndexOf("-Watch", [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
    $heartbeatPid = 0
    $heartbeatPidValid = $false
    if ($heartbeat -and [int]::TryParse([string]$heartbeat.pid, [ref]$heartbeatPid)) {
        $heartbeatPidValid = $heartbeatPid -gt 0
    }
    $heartbeatUpdatedAt = $null
    if ($heartbeat -and $heartbeat.updated_at) {
        try { $heartbeatUpdatedAt = [DateTimeOffset]::Parse([string]$heartbeat.updated_at).ToUniversalTime() } catch { $heartbeatUpdatedAt = $null }
    }
    $heartbeatAgeSeconds = if ($heartbeatUpdatedAt) {
        [Math]::Max(0, [int]([DateTimeOffset]::UtcNow - $heartbeatUpdatedAt).TotalSeconds)
    } else { $null }
    $heartbeatFresh = [bool]($heartbeat -and $heartbeatPidValid -and $heartbeatPid -eq $watcherPid -and
        $heartbeatAgeSeconds -ne $null -and $heartbeatAgeSeconds -le $HeartbeatMaxAgeSeconds -and
        [string]$heartbeat.status -ne "error")
    $running = [bool]($pidValid -and $processMatches -and $heartbeatFresh)
    $state = if ($heartbeat -and $heartbeat.status) { [string]$heartbeat.status } elseif ($running) { "unknown" } else { "stopped" }
    if (-not $running -and ($processMatches -or $heartbeat)) { $state = "stale" }

    return [PSCustomObject]@{
        running               = $running
        output_dir            = $DataDir
        pid                   = if ($pidValid) { $watcherPid } else { $null }
        process_exists        = [bool]$process
        process_matches       = $processMatches
        command_line          = $commandLine
        heartbeat_exists      = [bool]$heartbeat
        heartbeat_pid         = if ($heartbeatPidValid) { $heartbeatPid } else { $null }
        heartbeat_fresh       = $heartbeatFresh
        heartbeat_age_seconds = $heartbeatAgeSeconds
        status                = $state
        last_updated_at       = if ($heartbeat) { [string]$heartbeat.updated_at } else { "" }
        last_scan_at          = if ($heartbeat) { [string]$heartbeat.last_scan_at } else { "" }
        last_successful_scan_at = if ($heartbeat) { [string]$heartbeat.last_successful_scan_at } else { "" }
        last_error             = if ($heartbeat) { [string]$heartbeat.last_error } else { "" }
    }
}

function Test-CollectorWatcher {
    param([switch]$SkipVersionCheck)

    $pidPath = Join-Path $DataDir ".collector.pid"
    $heartbeatPath = Join-Path $DataDir ".collector-heartbeat.json"
    $status = Get-CollectorWatcherStatus
    $watcherPid = if ($status.pid) { [int]$status.pid } else { 0 }
    $process = if ($watcherPid -gt 0) { Get-Process -Id $watcherPid -ErrorAction SilentlyContinue } else { $null }
    if ($env:SKILL_TRACKER_DEBUG) {
        Write-Host "Watcher check PID=$watcherPid running=$($status.running) process=$([bool]$process) collector='$CollectorPath' status=$($status.status) heartbeat_age=$($status.heartbeat_age_seconds)"
    }
    if (-not $status.running) {
        if ($status.process_matches -and $process) {
            Stop-Process -Id $watcherPid -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $watcherPid -Timeout 5 -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $heartbeatPath -Force -ErrorAction SilentlyContinue
        return $false
    }

    if (-not $SkipVersionCheck) {
        try {
            $collectorWriteUtc = (Get-Item -LiteralPath $CollectorPath -ErrorAction Stop).LastWriteTimeUtc
            $watcherStartUtc = ([datetime]$process.StartTime).ToUniversalTime()
            if ($watcherStartUtc -lt $collectorWriteUtc) {
                Stop-Process -Id $watcherPid -Force -ErrorAction SilentlyContinue
                Wait-Process -Id $watcherPid -Timeout 5 -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $heartbeatPath -Force -ErrorAction SilentlyContinue
                return $false
            }
        } catch {
            # If process metadata is unavailable, ownership and the mutex
            # remain the safety checks.
        }
    }

    return $true
}

function Start-CollectorWatcher {
    if (Test-CollectorWatcher) { return $true }
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        if ($attempt -gt 0) {
            # A forced replacement can leave the named mutex in the old
            # process teardown window for a few hundred milliseconds.
            Start-Sleep -Milliseconds 500
        }
        try {
            $watcherProcess = Start-SkillTrackerPowerShell -ScriptPath $CollectorPath -ScriptArguments @("-ConfigFile", $resolvedConfigFile, "-Watch")
            if (-not $watcherProcess) { continue }
            $deadline = (Get-Date).AddSeconds(15)
            do {
                if (Test-CollectorWatcher -SkipVersionCheck) { return $true }
                if ($watcherProcess.HasExited) { break }
                Start-Sleep -Milliseconds 300
            } while ((Get-Date) -lt $deadline)
            if (Test-CollectorWatcher -SkipVersionCheck) { return $true }
            if (-not $watcherProcess.HasExited) { return $false }
        } catch {
            # Retry only startup failures; the final attempt reports the
            # unavailable watcher to the caller without masking the dashboard.
        }
    }
    return $false
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
    $managedServerProcesses = @(Get-ManagedSkillTrackerServerProcesses -ListenPort $Port)
    if ($managedServerProcesses.Count -gt 0) {
        Write-Host "Replacing the previous Skill Tracker server on port $Port..."
        if (-not (Stop-ManagedSkillTrackerServers -ListenPort $Port)) {
            throw "The previous Skill Tracker server on port $Port could not be stopped."
        }
        $stopDeadline = (Get-Date).AddSeconds(10)
        do {
            if (-not (Test-AnyHttpServer -ListenPort $Port)) { break }
            Start-Sleep -Milliseconds 250
        } while ((Get-Date) -lt $stopDeadline)
        if (Test-AnyHttpServer -ListenPort $Port) {
            throw "The previous Skill Tracker server on port $Port is still responding."
        }
    } elseif (Test-AnyHttpServer -ListenPort $Port) {
        throw "Port $Port is already used by another local server. Stop that server or choose another port."
    }

    Start-SkillTrackerPowerShell -ScriptPath $PSCommandPath -ScriptArguments @("-Server", "-Port", "$Port", "-ConfigFile", $resolvedConfigFile) | Out-Null
    if (-not (Wait-SkillTrackerServer -ListenPort $Port -TimeoutSeconds 20)) {
        throw "Dashboard server did not become ready on http://127.0.0.1:$Port/."
    }
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
    if (-not (Test-Path -LiteralPath (Join-Path $DataDir $file) -PathType Leaf)) {
        $hasGeneratedData = $false
        break
    }
}

if ($NoWatch -and (-not $hasGeneratedData -or $ForceScan)) {
    Write-Host "Reading local AI-agent logs..."
    & $CollectorPath -ConfigFile $resolvedConfigFile -ForceScan
    if (-not $?) {
        throw "Initial local collection failed."
    }
    Assert-GeneratedDashboardData
} elseif (-not $NoWatch) {
    if (Test-CollectorWatcher) {
        [System.IO.File]::WriteAllText($CollectorTriggerPath, [DateTimeOffset]::UtcNow.ToString("o"), [System.Text.Encoding]::UTF8)
        Write-Host "已请求后台收集器重新扫描本机工具与最新日志。"
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

if (-not $NoBrowser) {
    Open-SkillTrackerBrowser -Url "http://127.0.0.1:$Port/index.html"
}
