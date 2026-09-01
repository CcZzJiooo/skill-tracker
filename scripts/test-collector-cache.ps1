param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $repoRoot "collect.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-cache-" + [guid]::NewGuid().ToString("N"))
$fakeHome = Join-Path $tempRoot "home"
$skillsRoot = Join-Path $fakeHome "skills"
$skillDir = Join-Path $skillsRoot "cache-skill"
$externalSkillDir = Join-Path $tempRoot "external-project\.agents\skills\cached-discovered"
$logDir = Join-Path $fakeHome "custom-log"
$outputDir = Join-Path $tempRoot "dashboard"
$configPath = Join-Path $tempRoot "config.json"

function Invoke-Collection {
    $output = (& powershell -NoProfile -ExecutionPolicy Bypass -File $collector -ConfigFile $configPath -RecentFiles 0 -RecentDays 0 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "Collector failed: $output" }
    return $output
}

try {
    New-Item -ItemType Directory -Path $skillDir,$externalSkillDir,$logDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $skillDir "SKILL.md"),
        "---`nname: cache-skill`ndescription: Cache fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $externalSkillDir "SKILL.md"),
        "---`nname: cached-discovered`ndescription: Dynamically discovered cache fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    $logPath = Join-Path $logDir "session.jsonl"
    [System.IO.File]::WriteAllText(
        $logPath,
        ('{"type":"USER_INPUT","timestamp":"2026-08-05T01:00:00Z","text":"/cache-skill "}' + "`n" +
         '{"type":"VIEW_FILE","timestamp":"2026-08-05T01:30:00Z","content":"File Path: ' + (Join-Path $externalSkillDir 'SKILL.md').Replace('\','\\') + '"}' + "`n"),
        [System.Text.Encoding]::UTF8
    )
    $config = [ordered]@{
        skills_root = ""
        skills_roots = @($skillsRoot)
        output_dir = $outputDir
        max_log_entries = 100
        dedup_window_minutes = 2
        custom_tools = @([ordered]@{ name = "Cache Fixture"; path = $logDir })
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

        $first = Invoke-Collection
        if ($first -notmatch 'Cache:\s+0 reused,\s+1 parsed') { throw "First collection did not parse the fixture file once." }
        $firstLog = Get-Content -LiteralPath (Join-Path $outputDir "skill_log.js") -Raw -Encoding UTF8
        if ($firstLog -notmatch '"skill":"cached-discovered"') {
            $fixtureText = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8
            throw "First collection did not discover the project-local skill source.`nFixture: $fixtureText`nOutput: $firstLog"
        }
        $cachePayload = Get-Content -LiteralPath (Join-Path $outputDir ".collector-cache.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        $cachedDynamicHit = @($cachePayload.entries.PSObject.Properties | ForEach-Object { @($_.Value.raw_hits) } | Where-Object { $_.skill -eq "cached-discovered" }) | Select-Object -First 1
        if (-not $cachedDynamicHit -or -not $cachedDynamicHit.sourcePath) {
            throw "Dynamic skill source path was not persisted in the file cache."
        }

        $second = Invoke-Collection
        if ($second -notmatch 'Cache:\s+1 reused,\s+0 parsed') { throw "Second collection did not reuse the persistent file cache." }
        $secondLog = Get-Content -LiteralPath (Join-Path $outputDir "skill_log.js") -Raw -Encoding UTF8
        if ($secondLog -notmatch '"skill":"cached-discovered"') {
            throw "Cached dynamic skill source was not restored during cache reuse."
        }

        [System.IO.File]::AppendAllText($logPath, '{"type":"USER_INPUT","timestamp":"2026-08-05T02:00:00Z","text":"/cache-skill "}' + "`n", [System.Text.Encoding]::UTF8)
        [System.IO.File]::SetLastWriteTimeUtc($logPath, [DateTime]::UtcNow.AddSeconds(2))
    $third = Invoke-Collection
    if ($third -notmatch 'Cache:\s+0 reused,\s+1 parsed') { throw "Modified fixture file was not reparsed." }
    $stats = Get-Content -LiteralPath (Join-Path $outputDir "skill_call_stats.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if ((@($stats.skill_call_stats | Where-Object skill -eq "cache-skill")[0]).raw_count -lt 2) {
        throw "Reparsed cache fixture did not preserve both dated calls."
    }

    # A transient file lock must not replace the last good cache entry with an
    # empty successful-looking result. Once the lock is released, the changed
    # file must be retried and both calls must be visible.
    [System.IO.File]::AppendAllText($logPath, '{"type":"USER_INPUT","timestamp":"2026-08-05T03:00:00Z","text":"/cache-skill "}' + "`n", [System.Text.Encoding]::UTF8)
    [System.IO.File]::SetLastWriteTimeUtc($logPath, [DateTime]::UtcNow.AddSeconds(4))
    $lockStream = $null
    try {
        $lockStream = [System.IO.FileStream]::new(
            $logPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::None
        )
        Invoke-Collection | Out-Null
    } finally {
        if ($lockStream) { $lockStream.Dispose() }
    }

    $recovered = Invoke-Collection
    if ($recovered -notmatch 'Cache:\s+0 reused,\s+1 parsed') { throw "Collector did not retry a file after a transient read failure." }
    $recoveredStats = Get-Content -LiteralPath (Join-Path $outputDir "skill_call_stats.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if ((@($recoveredStats.skill_call_stats | Where-Object skill -eq "cache-skill")[0]).raw_count -lt 3) {
        throw "Collector lost cached calls after recovering from a transient file lock."
    }
} finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
        $env:APPDATA = $priorAppData
        $env:LOCALAPPDATA = $priorLocalAppData
    }

    Write-Host "Collector persistent cache test passed."
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
