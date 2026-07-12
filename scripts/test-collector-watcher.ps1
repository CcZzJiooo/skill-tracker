param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $repoRoot "collect.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-watcher-test-" + [guid]::NewGuid().ToString("N"))
$outputDir = Join-Path $tempRoot "dashboard"
$logDir = Join-Path $tempRoot "logs"
$configPath = Join-Path $tempRoot "config.json"
$secondOutput = Join-Path $tempRoot "second-watcher.log"

function Wait-ForFile {
    param(
        [string]$Path,
        [int]$TimeoutSeconds = 15
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (Test-Path -LiteralPath $Path -PathType Leaf) { return $true }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)
    return $false
}

try {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $logDir "watch.jsonl"),
        '{"type":"USER_INPUT","timestamp":"2026-07-12T12:00:00Z","text":"/watch-test-skill "}' + "`n",
        [System.Text.Encoding]::UTF8
    )
    $config = [ordered]@{
        skills_root = ""
        skills_roots = @()
        output_dir = $outputDir
        max_log_entries = 100
        dedup_window_minutes = 2
        custom_tools = @([ordered]@{ name = "Watch Test"; path = $logDir })
    }
    [System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)

    $first = Start-Process -FilePath "powershell" -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$collector`"",
        "-ConfigFile", "`"$configPath`"", "-Watch", "-RecentFiles", "20", "-RecentDays", "45"
    ) -PassThru -WindowStyle Hidden
    $pidPath = Join-Path $outputDir ".collector.pid"
    if (-not (Wait-ForFile -Path $pidPath)) {
        throw "First watcher did not create its PID file."
    }
    $firstPid = (Get-Content -LiteralPath $pidPath -Raw).Trim()
    if ($firstPid -ne [string]$first.Id) {
        throw "PID file did not identify the first watcher."
    }

    $second = Start-Process -FilePath "powershell" -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$collector`"",
        "-ConfigFile", "`"$configPath`"", "-Watch", "-RecentFiles", "20", "-RecentDays", "45"
    ) -PassThru -WindowStyle Hidden -RedirectStandardOutput $secondOutput
    if (-not $second.WaitForExit(10000)) {
        throw "Second watcher did not exit when a watcher was already active."
    }
    if ((Get-Content -LiteralPath $pidPath -Raw).Trim() -ne $firstPid) {
        throw "Second watcher replaced the active watcher's PID file."
    }

    Write-Host "Collector watcher singleton test passed."
} finally {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($tempRoot) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
