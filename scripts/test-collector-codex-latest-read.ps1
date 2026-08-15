param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $repoRoot "collect.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-codex-read-" + [guid]::NewGuid().ToString("N"))
$fakeHome = Join-Path $tempRoot "home"
$seedRoot = Join-Path $fakeHome "seed-skills"
$externalSkillDir = Join-Path $fakeHome "external\skills\codex-latest-skill"
$codexLogDir = Join-Path $fakeHome ".codex\sessions\2026\08\05"
$outputDir = Join-Path $tempRoot "dashboard"
$configPath = Join-Path $tempRoot "config.json"

try {
    New-Item -ItemType Directory -Path (Join-Path $seedRoot "seed-skill"),$externalSkillDir,$codexLogDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $seedRoot "seed-skill\SKILL.md"),
        "---`nname: seed-skill`ndescription: Seed fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    $skillFile = Join-Path $externalSkillDir "SKILL.md"
    [System.IO.File]::WriteAllText(
        $skillFile,
        "---`nname: codex-latest-skill`ndescription: Read from a new Codex tool-call record.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    $record = [ordered]@{
        timestamp = "2026-08-05T03:04:05Z"
        type = "response_item"
        payload = [ordered]@{
            type = "custom_tool_call"
            name = "exec"
            input = "Get-Content -Raw '$skillFile'"
        }
    }
    $recordLine = ($record | ConvertTo-Json -Compress)
    [System.IO.File]::WriteAllText(
        (Join-Path $codexLogDir "session.jsonl"),
        $recordLine + "`n",
        [System.Text.Encoding]::UTF8
    )
    $config = [ordered]@{
        skills_root = ""
        skills_roots = @($seedRoot)
        output_dir = $outputDir
        max_log_entries = 100
        dedup_window_minutes = 2
        custom_tools = @()
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
        & powershell -NoProfile -ExecutionPolicy Bypass -File $collector -ConfigFile $configPath -RecentFiles 0 -RecentDays 0 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Collector failed." }
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
        $env:APPDATA = $priorAppData
        $env:LOCALAPPDATA = $priorLocalAppData
    }

    $catalog = Get-Content -LiteralPath (Join-Path $outputDir "skill_catalog.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not @($catalog | Where-Object skill -eq "codex-latest-skill")) {
        throw "New Codex SKILL.md read did not discover the skill in the catalog."
    }
    $log = Get-Content -LiteralPath (Join-Path $outputDir "skill_log.js") -Raw -Encoding UTF8
    if ($log -notmatch '"skill":"codex-latest-skill"' -or $log -notmatch '"time":"2026-08-05T03:04:05Z"') {
        throw "Codex custom_tool_call did not produce the latest dated skill record."
    }

    Write-Host "Collector Codex latest-read test passed."
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
