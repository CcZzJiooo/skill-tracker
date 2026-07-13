param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $repoRoot "collect.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-watcher-new-skill-test-" + [guid]::NewGuid().ToString("N"))
$fakeHome = Join-Path $tempRoot "home"
$skillsRoot = Join-Path $fakeHome "installed-skills"
$initialSkillDir = Join-Path $skillsRoot "initial-skill"
$newSkillDir = Join-Path $skillsRoot "new-download-skill"
$outputDir = Join-Path $tempRoot "dashboard"
$configPath = Join-Path $tempRoot "config.json"

function Get-CatalogEntry {
    param(
        [string]$Path,
        [string]$Skill
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $raw = @(Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    foreach ($candidate in $raw) {
        foreach ($entry in @($candidate)) {
            if ($entry.skill -eq $Skill) { return $entry }
        }
    }
    return $null
}

function Wait-ForCatalogEntry {
    param(
        [string]$Path,
        [string]$Skill,
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $entry = Get-CatalogEntry -Path $Path -Skill $Skill
            if ($entry) { return $entry }
        } catch {
            # The watcher may be replacing the JSON file while this test reads it.
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $null
}

try {
    New-Item -ItemType Directory -Path $initialSkillDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $initialSkillDir "SKILL.md"),
        "---`nname: initial-skill`ndescription: Initial watcher fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    $config = [ordered]@{
        skills_root = ""
        skills_roots = @($skillsRoot)
        output_dir = $outputDir
        max_log_entries = 100
        dedup_window_minutes = 2
        custom_tools = @()
    }
    [System.IO.File]::WriteAllText(
        $configPath,
        ($config | ConvertTo-Json -Depth 5),
        [System.Text.Encoding]::UTF8
    )

    $priorUserProfile = $env:USERPROFILE
    $priorHome = $env:HOME
    try {
        $env:USERPROFILE = $fakeHome
        $env:HOME = $fakeHome
        $watcher = Start-Process -FilePath "powershell" -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$collector`"",
            "-ConfigFile", "`"$configPath`"", "-Watch", "-RecentFiles", "20", "-RecentDays", "45"
        ) -PassThru -WindowStyle Hidden
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
    }

    $catalogPath = Join-Path $outputDir "skill_catalog.json"
    if (-not (Wait-ForCatalogEntry -Path $catalogPath -Skill "initial-skill")) {
        throw "Watcher did not generate the initial local skill catalog."
    }

    New-Item -ItemType Directory -Path $newSkillDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $newSkillDir "SKILL.md"),
        "---`nname: new-download-skill`ndescription: Generate responsive web interfaces with React and accessibility checks.`n---`n",
        [System.Text.Encoding]::UTF8
    )

    $newEntry = Wait-ForCatalogEntry -Path $catalogPath -Skill "new-download-skill"
    if (-not $newEntry) {
        throw "Watcher did not discover a SKILL.md installed after startup."
    }
    if (-not [regex]::IsMatch([string]$newEntry.zh_desc, "\p{IsCJKUnifiedIdeographs}")) {
        throw "Watcher discovered the new skill but did not generate its Chinese summary."
    }
    if ([string]$newEntry.zh_desc_source -notmatch '^auto') {
        throw "Watcher did not mark the new Chinese summary as automatic."
    }

    Write-Host "Collector watcher new-skill translation test passed."
} finally {
    if ($watcher -and -not $watcher.HasExited) {
        Stop-Process -Id $watcher.Id -Force -ErrorAction SilentlyContinue
    }
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($tempRoot) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
