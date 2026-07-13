param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $repoRoot "collect.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-false-positive-test-" + [guid]::NewGuid().ToString("N"))
$fakeHome = Join-Path $tempRoot "home"
$logDir = Join-Path $fakeHome "portable-test-logs"
$skillsRoot = Join-Path $fakeHome "installed-skills"
$knownSkillDir = Join-Path $skillsRoot "known-tag-skill"
$portableSkillDir = Join-Path $skillsRoot "portable-test-skill"
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
    if (-not $line) {
        throw "Cannot find JS assignment: $Name in $Path"
    }
    $json = $line.Substring($prefix.Length).Trim()
    if ($json.EndsWith(";")) { $json = $json.Substring(0, $json.Length - 1) }
    return @($json | ConvertFrom-Json)
}

try {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    New-Item -ItemType Directory -Path $knownSkillDir -Force | Out-Null
    New-Item -ItemType Directory -Path $portableSkillDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $knownSkillDir "SKILL.md"),
        "---`nname: known-tag-skill`ndescription: Test fixture for a tagged skill command.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $portableSkillDir "SKILL.md"),
        "---`nname: portable-test-skill`ndescription: Test fixture for an explicit skill command.`n---`n",
        [System.Text.Encoding]::UTF8
    )

    $validCommand = [ordered]@{
        source = "USER_EXPLICIT"
        type = "USER_INPUT"
        timestamp = "2026-07-12T12:00:00Z"
        content = "<USER_REQUEST>`n/portable-test-skill`n/documents`n/github`n/goal`n</USER_REQUEST>`n<ADDITIONAL_METADATA>`nOpen file: C:/workspace/metadata-token`n</ADDITIONAL_METADATA>"
    } | ConvertTo-Json -Compress
    $pdfPreview = [ordered]@{
        source = "USER_EXPLICIT"
        type = "VIEW_FILE"
        timestamp = "2026-07-12T12:01:00Z"
        content = "PDF object data: /Contents 4 0 R /FontFile2 5216 0 R /c /looks-like-a-skill "
    } | ConvertTo-Json -Compress
    $commandTag = [ordered]@{
        timestamp = "2026-07-12T12:02:00Z"
        type = "response_item"
        payload = [ordered]@{
            type = "message"
            role = "user"
            content = @(
                [ordered]@{
                    type = "input_text"
                    text = "<command-name>/known-tag-skill</command-name> <command-name>/model</command-name>"
                }
            )
        }
    } | ConvertTo-Json -Depth 8 -Compress
    $skillsLockPreview = [ordered]@{
        source = "MODEL"
        type = "VIEW_FILE"
        timestamp = "2026-07-12T12:03:00Z"
        content = "File Path: `file:///C:/workspace/skills-lock.json``nLock entry: skills/devlink-command/SKILL.md"
    } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText(
        (Join-Path $logDir "session.jsonl"),
        "$validCommand`n$pdfPreview`n$commandTag`n$skillsLockPreview`n",
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
                name = "Portable Test"
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
    try {
        $env:USERPROFILE = $fakeHome
        $env:HOME = $fakeHome
        & powershell -NoProfile -ExecutionPolicy Bypass -File $collector -ConfigFile $configPath -OutputDir $outputDir -RecentFiles 20 -RecentDays 45
        if ($LASTEXITCODE -ne 0) {
            throw "Collector exited with code $LASTEXITCODE for the false-positive fixture."
        }
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
    }

    $skills = @(Read-JsArray -Path (Join-Path $outputDir "skill_log.js") -Name "SKILL_LOG" |
        ForEach-Object { $_.skill })
    if ($skills -notcontains "portable-test-skill") {
        throw "Collector did not retain the explicit skill command."
    }

    $falsePositives = @("Contents", "FontFile2", "c", "looks-like-a-skill", "metadata-token", "model", "documents", "devlink-command", "github", "goal")
    $emittedFalsePositives = @($skills | Where-Object { $falsePositives -contains $_ })
    if ($emittedFalsePositives.Count) {
        throw ("Collector treated file content as skill commands: " + ($emittedFalsePositives -join ", "))
    }

    $expectedSkills = @("known-tag-skill", "portable-test-skill")
    if (@($skills | Where-Object { $expectedSkills -notcontains $_ }).Count -gt 0 -or
        @($expectedSkills | Where-Object { $skills -notcontains $_ }).Count -gt 0) {
        throw ("Unexpected detected skills: " + ($skills -join ", "))
    }

    Write-Host "Collector false-positive skill test passed."
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
