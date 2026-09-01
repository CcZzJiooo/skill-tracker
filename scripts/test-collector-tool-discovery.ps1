param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $repoRoot "collect.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-tool-discovery-" + [guid]::NewGuid().ToString("N"))
$fakeHome = Join-Path $tempRoot "home"
$skillsRoot = Join-Path $fakeHome "skills"
$skillDir = Join-Path $skillsRoot "adaptive-discovery-skill"
$openCodeLogDir = Join-Path $fakeHome "AppData\Roaming\opencode\log"
$openCodeInstallDir = Join-Path $fakeHome "AppData\Local\Programs\OpenCode"
$openCodeInstallPath = Join-Path $openCodeInstallDir "opencode.exe"
$dshLogDir = Join-Path $fakeHome ".dsh\sessions"
$dshInstallDir = Join-Path $fakeHome ".dsh\bin"
$dshInstallPath = Join-Path $dshInstallDir "dsh.cmd"
$dshNpxCacheDir = Join-Path $fakeHome "AppData\Local\npm-cache\_npx\fixture"
$dshNpxPackageDir = Join-Path $dshNpxCacheDir "node_modules\@deepseek-ai\dsh"
$dshNpxPackagePath = Join-Path $dshNpxPackageDir "package.json"
$kiroInstallDir = Join-Path $fakeHome "AppData\Local\Programs\Kiro"
$kiroInstallPath = Join-Path $kiroInstallDir "Kiro.exe"
$outputDir = Join-Path $tempRoot "dashboard"
$configPath = Join-Path $tempRoot "config.json"

function Write-Config {
    $config = [ordered]@{
        skills_root = ""
        skills_roots = @($skillsRoot)
        output_dir = $outputDir
        max_log_entries = 100
        dedup_window_minutes = 2
        custom_tools = @()
    }
    [System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)
}

function Invoke-Collection {
    $output = (& powershell -NoProfile -ExecutionPolicy Bypass -File $collector -ConfigFile $configPath -RecentFiles 0 -RecentDays 0 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "Collector failed: $output" }
    return $output
}

function Read-Report {
    return Get-Content -LiteralPath (Join-Path $outputDir "tool_report.json") -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-Names {
    param([object]$Value)
    return @($Value | ForEach-Object { [string]$_ })
}

try {
    New-Item -ItemType Directory -Path $skillDir,$openCodeLogDir,$openCodeInstallDir,$dshLogDir,$dshInstallDir,$dshNpxPackageDir,$kiroInstallDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $skillDir "SKILL.md"),
        "---`nname: adaptive-discovery-skill`ndescription: Tool discovery fixture.`n---`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $openCodeLogDir "opencode.log"),
        '{"type":"user","timestamp":"2026-08-31T01:00:00Z","text":"/adaptive-discovery-skill "}' + "`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $dshLogDir "session.jsonl"),
        '{ "type": "user/message", "time": 1788138060000, "data": { "content": [ { "type": "text", "text": "/adaptive-discovery-skill " } ], "source": { "kind": "user" } } }' + "`n",
        [System.Text.Encoding]::UTF8
    )
    [System.IO.File]::WriteAllText($dshNpxPackagePath, '{"name":"@deepseek-ai/dsh","version":"0.1.0"}', [System.Text.Encoding]::UTF8)
    New-Item -ItemType File -Path $openCodeInstallPath,$kiroInstallPath -Force | Out-Null
    Write-Config

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

        Invoke-Collection | Out-Null
        $first = Read-Report
        $firstVisible = Get-Names $first.summary.supported_tools
        if ($firstVisible -notcontains "OpenCode" -or $firstVisible -notcontains "DeepSeek Harness") {
            throw "v0.6 discovery did not expose the installed OpenCode and DeepSeek Harness profiles: $($firstVisible -join ', ')"
        }
        if ($firstVisible -ccontains "opencode" -or $firstVisible -ccontains "deepseekharness" -or $firstVisible -ccontains "dsh" -or $firstVisible -ccontains "DeepSeek") {
            throw "Tool names were not canonicalized: $($firstVisible -join ', ')"
        }
        $candidates = @($first.discovery.unknown_candidates | ForEach-Object { [string]$_.name })
        if ($candidates -notcontains "Kiro") {
            throw "The bounded candidate probe did not surface an installed but not-yet-adapted tool: $($candidates -join ', ')"
        }
        $firstTools = Get-Names ($first.tools | Select-Object -ExpandProperty tool)
        if ($firstTools -ccontains "opencode" -or $firstTools -ccontains "deepseekharness" -or $firstTools -ccontains "dsh") {
            throw "The tool summary still contains legacy OpenCode/DeepSeek Harness names."
        }
        $firstRows = @($first.sources | Where-Object { $_.detected })
        $openCodeRows = @($firstRows | Where-Object { $_.tool -eq "OpenCode" })
        $dshRows = @($firstRows | Where-Object { $_.tool -eq "DeepSeek Harness" })
        if (-not $openCodeRows -or -not $dshRows) {
            throw "Installed OpenCode and DeepSeek Harness source rows were not detected."
        }
        $skillLogText = Get-Content -LiteralPath (Join-Path $outputDir "skill_log.js") -Raw -Encoding UTF8
        if ($skillLogText -notmatch '"tool":"OpenCode"' -or $skillLogText -notmatch '"tool":"DeepSeek Harness"') {
            throw "OpenCode/DeepSeek Harness skill calls were not written to the public skill log."
        }
        if ($skillLogText -notmatch '2026-08-31T01:00:00Z' -or $skillLogText -notmatch '2026-08-31T01:01:00Z') {
            throw "OpenCode/DeepSeek Harness timestamps were not parsed from their native log fields."
        }

        Remove-Item -LiteralPath $openCodeInstallDir,$dshInstallDir,$dshNpxCacheDir,$kiroInstallDir -Recurse -Force
        Invoke-Collection | Out-Null
        $second = Read-Report
        $secondVisible = Get-Names $second.summary.supported_tools
        if ($secondVisible -contains "OpenCode" -or $secondVisible -contains "DeepSeek Harness") {
            throw "Removed tools remained in the visible supported_tools list: $($secondVisible -join ', ')"
        }
        $removed = Get-Names $second.discovery.removed_tools
        if ($removed -notcontains "OpenCode" -or $removed -notcontains "DeepSeek Harness") {
            throw "Removed tool history was not recorded: $($removed -join ', ')"
        }
        $openCodeRows = @($second.sources | Where-Object { $_.tool -eq "OpenCode" })
        $dshRows = @($second.sources | Where-Object { $_.tool -eq "DeepSeek Harness" })
        if (-not $openCodeRows -or -not $dshRows) {
            throw "Diagnostic source rows disappeared; the report must retain evidence explaining why a tool was hidden."
        }
        if (@($openCodeRows | Where-Object { $_.detected }).Count -gt 0 -or @($dshRows | Where-Object { $_.detected }).Count -gt 0) {
            throw "A removed tool was still scanned from its historical log directory."
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

    Write-Host "Collector adaptive tool discovery test passed."
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
