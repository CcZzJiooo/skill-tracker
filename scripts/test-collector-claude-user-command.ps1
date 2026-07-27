param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $repoRoot "collect.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-claude-user-test-" + [guid]::NewGuid().ToString("N"))
$logDir = Join-Path $tempRoot "claude-project"
$skillsRoot = Join-Path $tempRoot "installed-skills"
$skillDir = Join-Path $skillsRoot "claude-user-skill"
$outputDir = Join-Path $tempRoot "dashboard"
    $configPath = Join-Path $tempRoot "config.json"

function Read-JsArray {
    param(
        [string]$Path,
        [string]$Name
    )

    $prefix = "var $Name = "
    $line = Get-Content -LiteralPath $Path -Encoding UTF8 |
        Where-Object { $_.StartsWith($prefix) } |
        Select-Object -First 1
    if (-not $line) { throw "Cannot find JS assignment: $Name in $Path" }
    $json = $line.Substring($prefix.Length).Trim()
    if ($json.EndsWith(";")) { $json = $json.Substring(0, $json.Length - 1) }
    return @($json | ConvertFrom-Json)
}

try {
    New-Item -ItemType Directory -Path $logDir,$skillDir,$outputDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $skillDir "SKILL.md"),
        "---`nname: claude-user-skill`ndescription: Claude legacy user command fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )

    $claudeUser = [ordered]@{
        type = "user"
        timestamp = "2026-07-27T08:30:00.000Z"
        message = [ordered]@{
            role = "user"
            content = "<command-name>/claude-user-skill</command-name>"
        }
    } | ConvertTo-Json -Depth 8 -Compress
    [System.IO.File]::WriteAllText(
        (Join-Path $logDir "session.jsonl"),
        $claudeUser + "`n",
        [System.Text.Encoding]::UTF8
    )

    $config = [ordered]@{
        skills_root = ""
        skills_roots = @($skillsRoot)
        output_dir = $outputDir
        max_log_entries = 100
        dedup_window_minutes = 2
        custom_tools = @(
            [ordered]@{
                name = "Claude Legacy Fixture"
                path = $logDir
            }
        )
    }
    [System.IO.File]::WriteAllText(
        $configPath,
        ($config | ConvertTo-Json -Depth 5),
        [System.Text.Encoding]::UTF8
    )

    $priorUserProfile = $env:USERPROFILE
    $priorHome = $env:HOME
    $priorAppData = $env:APPDATA
    $priorLocalAppData = $env:LOCALAPPDATA
    try {
        $env:USERPROFILE = Join-Path $tempRoot "home"
        $env:HOME = $env:USERPROFILE
        $env:APPDATA = Join-Path $env:USERPROFILE "AppData\Roaming"
        $env:LOCALAPPDATA = Join-Path $env:USERPROFILE "AppData\Local"
        & powershell -NoProfile -ExecutionPolicy Bypass -File $collector -ConfigFile $configPath -OutputDir $outputDir -RecentFiles 20 -RecentDays 45
        if ($LASTEXITCODE -ne 0) { throw "Collector exited with code $LASTEXITCODE for the Claude legacy fixture." }
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
        $env:APPDATA = $priorAppData
        $env:LOCALAPPDATA = $priorLocalAppData
    }

    $rows = @(Read-JsArray -Path (Join-Path $outputDir "skill_log.js") -Name "SKILL_LOG")
    $match = $rows | Where-Object { $_.skill -eq "claude-user-skill" } | Select-Object -First 1
    if (-not $match) { throw "Collector did not detect Claude's legacy type=user command record." }
    if ([string]$match.time -ne "2026-07-27T08:30:00.000Z") {
        throw "Collector did not preserve the Claude command timestamp: $($match.time)"
    }

    Write-Host "Collector Claude legacy user command test passed."
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
