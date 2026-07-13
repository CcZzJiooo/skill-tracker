param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $repoRoot "collect.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-auto-translation-test-" + [guid]::NewGuid().ToString("N"))
$fakeHome = Join-Path $tempRoot "home"
$skillsRoot = Join-Path $fakeHome "installed-skills"
$autoSkillDir = Join-Path $skillsRoot "frontend-audit-skill"
$manualSkillDir = Join-Path $skillsRoot "manual-zh-skill"
$outputDir = Join-Path $tempRoot "dashboard"
$configPath = Join-Path $tempRoot "config.json"
$manualDescription = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("6L+Z5piv5Lq65bel57u05oqk55qE5Lit5paH6K+05piO77yM5Yi35paw5ZCO5LiN5b6X6KaG55uW44CC"))

function Invoke-TestCollector {
    param(
        [string]$Collector,
        [string]$ConfigPath,
        [string]$OutputDir,
        [string]$FakeHome
    )

    $priorUserProfile = $env:USERPROFILE
    $priorHome = $env:HOME
    try {
        $env:USERPROFILE = $FakeHome
        $env:HOME = $FakeHome
        & powershell -NoProfile -ExecutionPolicy Bypass -File $Collector -ConfigFile $ConfigPath -OutputDir $OutputDir -RecentFiles 20 -RecentDays 45
        if ($LASTEXITCODE -ne 0) {
            throw "Collector exited with code $LASTEXITCODE for the auto-translation fixture."
        }
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
    }
}

function Get-CatalogEntry {
    param(
        [object[]]$Catalog,
        [string]$Skill
    )

    $items = @()
    foreach ($candidate in $Catalog) {
        foreach ($record in @($candidate)) {
            if ($record.skill -eq $Skill) {
                $items += $record
            }
        }
    }
    if ($items.Count -ne 1) {
        throw "Expected exactly one catalog entry for $Skill, found $($items.Count)."
    }
    return $items[0]
}

try {
    New-Item -ItemType Directory -Path $autoSkillDir -Force | Out-Null
    New-Item -ItemType Directory -Path $manualSkillDir -Force | Out-Null
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

    [System.IO.File]::WriteAllText(
        (Join-Path $autoSkillDir "SKILL.md"),
        @"
---
name: frontend-audit-skill
description: |
  Review React and Next.js interfaces for accessibility, responsive layout,
  interaction problems, and visual consistency. Use when auditing a web UI before release.
triggers:
  - audit UI
  - accessibility review
---

# Frontend audit

Inspect the interface before release and report concrete fixes.
"@,
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $manualSkillDir "SKILL.md"),
        "---`nname: manual-zh-skill`ndescription: A fixture whose Chinese summary is maintained by a person.`n---`n",
        [System.Text.Encoding]::UTF8
    )

    $existingCatalog = @(
        [ordered]@{
            skill = "manual-zh-skill"
            category = "General"
            zh_desc = $manualDescription
            zh_desc_source = "manual"
            english_desc = ""
            triggers = @()
            source_path = ""
        }
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $outputDir "skill_catalog.json"),
        ($existingCatalog | ConvertTo-Json -Depth 6),
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

    Invoke-TestCollector -Collector $collector -ConfigPath $configPath -OutputDir $outputDir -FakeHome $fakeHome

    $catalogPath = Join-Path $outputDir "skill_catalog.json"
    $catalog = @(Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    $auto = Get-CatalogEntry -Catalog $catalog -Skill "frontend-audit-skill"
    $manual = Get-CatalogEntry -Catalog $catalog -Skill "manual-zh-skill"

    $autoZhDesc = [string]$auto.zh_desc
    if ($autoZhDesc.Length -eq 0 -or -not [regex]::IsMatch($autoZhDesc, "\p{IsCJKUnifiedIdeographs}")) {
        throw "New English-only SKILL.md did not receive an automatic Chinese summary."
    }
    if ([string]$auto.zh_desc -ceq [string]$auto.english_desc) {
        throw "Automatic Chinese summary must not be a copy of the English description."
    }
    if ([string]$auto.zh_desc_source -notmatch '^auto') {
        throw "Automatic Chinese summary did not declare an automatic source."
    }
    if ([string]$auto.english_desc -notmatch 'Review React and Next\.js interfaces') {
        throw "Multiline frontmatter description was not parsed into the catalog."
    }
    if ([string]($auto.triggers | ConvertTo-Json -Compress) -notmatch 'audit UI') {
        throw "Frontmatter triggers were not preserved in the catalog."
    }
    if ([string]$manual.zh_desc -cne $manualDescription -or [string]$manual.zh_desc_source -cne "manual") {
        throw "Existing manual Chinese summary was overwritten."
    }

    Invoke-TestCollector -Collector $collector -ConfigPath $configPath -OutputDir $outputDir -FakeHome $fakeHome
    $secondCatalog = @(Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    $secondManual = Get-CatalogEntry -Catalog $secondCatalog -Skill "manual-zh-skill"
    if ([string]$secondManual.zh_desc -cne $manualDescription -or [string]$secondManual.zh_desc_source -cne "manual") {
        throw "Manual Chinese summary was overwritten on a later collection run."
    }

    Write-Host "Collector automatic Chinese translation test passed."
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
