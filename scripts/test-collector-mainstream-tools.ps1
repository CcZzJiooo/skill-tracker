param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-mainstream-tools-test-" + [guid]::NewGuid().ToString("N"))
$fakeHome = Join-Path $tempRoot "home"
$skillsRoot = Join-Path $fakeHome "skills"
$outputDir = Join-Path $tempRoot "dashboard"
$configPath = Join-Path $tempRoot "config.json"

function Read-Report {
    return Get-Content -LiteralPath (Join-Path $outputDir "tool_report.json") -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Invoke-Collection {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "collect.ps1") -ConfigFile $configPath -ForceScan
    if ($LASTEXITCODE -ne 0) { throw "Collector exited with code $LASTEXITCODE." }
}

function Get-Names {
    param([object]$Value)
    return @($Value | ForEach-Object { [string]$_ })
}

try {
    $workBuddyLogDir = Join-Path $fakeHome ".workbuddy\projects\c-WorkBuddy"
    $codeBuddyLogDir = Join-Path $fakeHome ".codebuddy\logs"
    $qoderLogDir = Join-Path $fakeHome ".qoder\projects\c-Qoder"
    $codeGeeXLogDir = Join-Path $fakeHome "AppData\Roaming\Code\User\globalStorage\AMiner.codegeex"
    $comateLogDir = Join-Path $fakeHome "AppData\Roaming\Code\User\globalStorage\BaiduComate.BaiduComate"
    $workBuddyInstallDir = Join-Path $fakeHome "AppData\Local\Programs\WorkBuddy"
    $codeBuddyInstallDir = Join-Path $fakeHome "AppData\Local\Programs\CodeBuddy"
    $qoderInstallDir = Join-Path $fakeHome "AppData\Local\Programs\Qoder"
    $codeGeeXInstallDir = Join-Path $fakeHome "AppData\Roaming\Code\User\extensions\AMiner.codegeex-1.1.2"
    $comateInstallDir = Join-Path $fakeHome "AppData\Roaming\Code\User\extensions\BaiduComate.BaiduComate-1.0.0"

    New-Item -ItemType Directory -Path $skillsRoot,$outputDir,$workBuddyLogDir,$codeBuddyLogDir,$qoderLogDir,$codeGeeXLogDir,$comateLogDir,$workBuddyInstallDir,$codeBuddyInstallDir,$qoderInstallDir,$codeGeeXInstallDir,$comateInstallDir -Force | Out-Null
    $skillDir = Join-Path $skillsRoot "mainstream-discovery-skill"
    New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $skillDir "SKILL.md"),
        "---`nname: mainstream-discovery-skill`ndescription: Mainstream tool fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $workBuddyLogDir "session.jsonl"),
        '{ "type": "message", "timestamp": 1788138120000, "role": "user", "content": [ { "type": "input_text", "text": "/mainstream-discovery-skill " } ], "sessionId": "workbuddy-fixture" }' + "`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $codeBuddyLogDir "session.jsonl"),
        '{"type":"user","timestamp":"2026-08-31T01:03:00Z","message":{"content":"/mainstream-discovery-skill "}}' + "`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $qoderLogDir "session.jsonl"),
        '{"type":"user","timestamp":"2026-08-31T01:04:00Z","content":"/mainstream-discovery-skill "}' + "`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $codeGeeXLogDir "session.log"),
        '{"type":"message","timestamp":"2026-08-31T01:05:00Z","role":"user","content":[{"type":"input_text","text":"/mainstream-discovery-skill "}]}' + "`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $comateLogDir "session.log"),
        '{"type":"message","timestamp":"2026-08-31T01:06:00Z","role":"user","content":"/mainstream-discovery-skill "}' + "`n",
        [System.Text.Encoding]::UTF8
    )
    foreach ($path in @(
        (Join-Path $workBuddyInstallDir "WorkBuddy.exe"),
        (Join-Path $codeBuddyInstallDir "CodeBuddy.exe"),
        (Join-Path $qoderInstallDir "Qoder.exe"),
        (Join-Path $codeGeeXInstallDir "package.json"),
        (Join-Path $comateInstallDir "package.json")
    )) {
        New-Item -ItemType File -Path $path -Force | Out-Null
    }
    [System.IO.File]::WriteAllText((Join-Path $codeGeeXInstallDir "package.json"), '{"publisher":"AMiner","name":"codegeex"}', [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText((Join-Path $comateInstallDir "package.json"), '{"publisher":"BaiduComate","name":"BaiduComate"}', [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText(
        $configPath,
        (@{
            skills_root = ""
            skills_roots = @($skillsRoot)
            output_dir = $outputDir
            max_log_entries = 100
            dedup_window_minutes = 2
            custom_tools = @()
        } | ConvertTo-Json -Depth 5),
        [System.Text.Encoding]::UTF8
    )

    $priorUserProfile = $env:USERPROFILE
    $priorHome = $env:HOME
    $priorAppData = $env:APPDATA
    $priorLocalAppData = $env:LOCALAPPDATA
    $priorProgramFiles = $env:ProgramFiles
    $priorPath = $env:PATH
    $priorProgramFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)", "Process")
    try {
        $env:USERPROFILE = $fakeHome
        $env:HOME = $fakeHome
        $env:APPDATA = Join-Path $fakeHome "AppData\Roaming"
        $env:LOCALAPPDATA = Join-Path $fakeHome "AppData\Local"
        $env:ProgramFiles = Join-Path $fakeHome "ProgramFiles"
        $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
        [Environment]::SetEnvironmentVariable("ProgramFiles(x86)", (Join-Path $fakeHome "ProgramFiles-x86"), "Process")

        Invoke-Collection
        $first = Read-Report
        $expected = @("WorkBuddy", "CodeBuddy", "Qoder", "CodeGeeX", "Baidu Comate")
        $visible = Get-Names $first.summary.supported_tools
        foreach ($tool in $expected) {
            if ($visible -notcontains $tool) { throw "Mainstream tool was not discovered: $tool; got $($visible -join ', ')" }
            if (@($first.sources | Where-Object { $_.tool -eq $tool -and $_.detected }).Count -eq 0) { throw "Detected source row is missing for $tool." }
        }
        if ($visible -contains "Tongyi Lingma" -or $visible -contains "通义灵码") {
            throw "Qoder legacy aliases leaked into the current tool list: $($visible -join ', ')"
        }
        $skillLogText = Get-Content -LiteralPath (Join-Path $outputDir "skill_log.js") -Raw -Encoding UTF8
        foreach ($tool in $expected) {
            if ($skillLogText -notmatch ('"tool":"' + [regex]::Escape($tool) + '"')) { throw "Skill log did not contain a row for $tool." }
        }
        if ($skillLogText -notmatch '2026-08-31T01:02:00Z') { throw "WorkBuddy numeric timestamp was not normalized." }

        Remove-Item -LiteralPath $workBuddyInstallDir,$codeBuddyInstallDir,$qoderInstallDir,$codeGeeXInstallDir,$comateInstallDir -Recurse -Force
        Invoke-Collection
        $second = Read-Report
        $secondVisible = Get-Names $second.summary.supported_tools
        foreach ($tool in $expected) {
            if ($secondVisible -contains $tool) { throw "Removed tool remained visible from stale logs: $tool" }
            if (@($second.sources | Where-Object { $_.tool -eq $tool }).Count -eq 0) { throw "Diagnostic source row disappeared for removed tool: $tool" }
        }
        $removed = Get-Names $second.discovery.removed_tools
        foreach ($tool in $expected) {
            if ($removed -notcontains $tool) { throw "Removed tool transition was not recorded: $tool" }
        }
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
        $env:APPDATA = $priorAppData
        $env:LOCALAPPDATA = $priorLocalAppData
        $env:ProgramFiles = $priorProgramFiles
        $env:PATH = $priorPath
        [Environment]::SetEnvironmentVariable("ProgramFiles(x86)", $priorProgramFilesX86, "Process")
    }

    Write-Host "Collector mainstream tool adaptation test passed."
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
