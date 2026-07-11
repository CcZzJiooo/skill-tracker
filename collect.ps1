<#
.SYNOPSIS
  Skill Tracker — collect AI skill call logs across all AI coding tools.
#>
param(
    [string]$SkillsRoot = "",
    [string]$ConfigFile = "$PSScriptRoot\config.json",
    [string]$OutputDir  = "",
    [switch]$Watch,
    [int]$RecentFiles = 250,
    [int]$RecentDays = 45
)

# ── Load config ────────────────────────────────────────────────────────────────
$cfg = @{ skills_root=""; skills_roots=@(); output_dir="./dashboard"; max_log_entries=5000; dedup_window_minutes=2; custom_tools=@() }
if (Test-Path $ConfigFile) {
    try {
        $raw = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        if ($raw.skills_root)     { $cfg.skills_root     = $raw.skills_root }
        if ($raw.skills_roots)    { $cfg.skills_roots    = $raw.skills_roots }
        if ($raw.output_dir)      { $cfg.output_dir      = $raw.output_dir }
        if ($raw.max_log_entries)      { $cfg.max_log_entries      = [int]$raw.max_log_entries }
        if ($raw.dedup_window_minutes) { $cfg.dedup_window_minutes = [int]$raw.dedup_window_minutes }
        if ($raw.custom_tools)         { $cfg.custom_tools         = $raw.custom_tools }
    } catch { Write-Warning "Could not parse config.json, using defaults." }
}
if ($SkillsRoot) { $cfg.skills_root = $SkillsRoot }
if ($OutputDir)  { $cfg.output_dir  = $OutputDir }
if (-not [System.IO.Path]::IsPathRooted($cfg.output_dir)) {
    $cfg.output_dir = Join-Path $PSScriptRoot $cfg.output_dir
}
New-Item -ItemType Directory -Path $cfg.output_dir -Force | Out-Null

# ── Auto-detect skills roots ───────────────────────────────────────────────────
$userHome = $env:USERPROFILE
if (-not $userHome) { $userHome = $env:HOME }
$appData = $env:APPDATA
if (-not $appData -and $userHome) { $appData = Join-Path $userHome "AppData\Roaming" }
$localAppData = $env:LOCALAPPDATA
if (-not $localAppData -and $userHome) { $localAppData = Join-Path $userHome "AppData\Local" }

$editorGlobalStorageRoots = @(
    "$appData\Code\User\globalStorage",
    "$appData\Code - Insiders\User\globalStorage",
    "$appData\VSCodium\User\globalStorage",
    "$appData\Cursor\User\globalStorage",
    "$appData\Windsurf\User\globalStorage",
    "$appData\Trae\User\globalStorage",
    "$appData\Trae CN\User\globalStorage"
)
$editorWorkspaceStorageRoots = @(
    "$appData\Code\User\workspaceStorage",
    "$appData\Code - Insiders\User\workspaceStorage",
    "$appData\VSCodium\User\workspaceStorage",
    "$appData\Cursor\User\workspaceStorage",
    "$appData\Windsurf\User\workspaceStorage",
    "$appData\Trae\User\workspaceStorage",
    "$appData\Trae CN\User\workspaceStorage"
)

function Get-EditorGlobalStoragePaths {
    param([string[]]$ExtensionIds)
    $paths = @()
    foreach ($root in $editorGlobalStorageRoots) {
        if (-not $root) { continue }
        foreach ($id in $ExtensionIds) {
            $paths += (Join-Path $root $id)
        }
    }
    return $paths
}

$skillRootCandidates = @(
    "$PSScriptRoot\.agents\skills",
    "$PSScriptRoot\.cursor\skills",
    "$PSScriptRoot\.codex\skills",
    "$userHome\.codex\skills",
    "$userHome\.agents\skills",
    "$userHome\.config\agents\skills",
    "$userHome\.claude\skills",
    "$userHome\.hermes\skills",
    "$userHome\.cursor\skills",
    "$userHome\.cline\skills",
    "$userHome\.roo\skills",
    "$userHome\.kilo\skills",
    "$userHome\.qwen\skills",
    "$userHome\.config\amp\skills",
    "$userHome\.config\opencode\skills",
    "$userHome\.opencode\skills",
    "$userHome\.gemini\config\skills",
    "$userHome\.config\gemini\skills",
    "$userHome\.cc-switch\skills"
)
$skillRoots = [System.Collections.Generic.List[string]]::new()
$skillRootKeys = @{}
function Add-SkillRoot {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (-not $skillRootKeys.ContainsKey($resolved)) {
        $skillRoots.Add($resolved)
        $skillRootKeys[$resolved] = $true
    }
}
if ($cfg.skills_root) { Add-SkillRoot -Path $cfg.skills_root }
foreach ($root in @($cfg.skills_roots)) { Add-SkillRoot -Path ([string]$root) }
if ($skillRoots.Count -eq 0) {
    foreach ($c in $skillRootCandidates) { Add-SkillRoot -Path $c }
}
if ($skillRoots.Count -eq 0) {
    Write-Error "Cannot find skills directory. Set 'skills_root' or 'skills_roots' in config.json."
    exit 1
}
Write-Host "Skills roots:"
foreach ($root in $skillRoots) { Write-Host "  $root" }

# ── Auto-detect installed AI tools ────────────────────────────────────────────
# Each tool specifies: Name, one or more scan roots, and a timestamp field preference
$AUTO_DETECT_TOOLS = @(
    @{ Name="Antigravity"; Paths=@("$userHome\.gemini\antigravity-ide\brain"); TsField="created_at" },
    @{ Name="Aider";       Paths=@("$PSScriptRoot\.aider.chat.history.md","$PSScriptRoot\.aider.llm.history","$userHome\.aider.chat.history.md","$userHome\.aider.llm.history"); TsField="timestamp" },
    @{ Name="Amazon Q";    Paths=@(Get-EditorGlobalStoragePaths -ExtensionIds @("amazonwebservices.amazon-q-vscode","amazonwebservices.aws-toolkit-vscode")); TsField="timestamp" },
    @{ Name="Amp";         Paths=@("$userHome\.config\amp","$userHome\AppData\Roaming\amp","$localAppData\amp"); TsField="timestamp" },
    @{ Name="Augment";     Paths=@(Get-EditorGlobalStoragePaths -ExtensionIds @("augment.vscode-augment","augment.vscode-augment-nightly")); TsField="timestamp" },
    @{ Name="ClaudeCode";  Paths=@("$userHome\.claude\projects"); TsField="timestamp" },
    @{ Name="Cline";       Paths=@(Get-EditorGlobalStoragePaths -ExtensionIds @("saoudrizwan.claude-dev","cline.cline")); TsField="timestamp" },
    @{ Name="Codex";       Paths=@("$userHome\.codex\archived_sessions","$userHome\.codex\sessions"); TsField="timestamp" },
    @{ Name="Cursor";      Paths=@("$userHome\.cursor\logs","$userHome\AppData\Roaming\Cursor\logs"); TsField="timestamp" },
    @{ Name="Windsurf";    Paths=@("$userHome\.codeium\windsurf\logs","$userHome\AppData\Roaming\Windsurf\logs"); TsField="timestamp" },
    @{ Name="Continue";    Paths=@("$userHome\.continue\sessions"); TsField="timestamp" },
    @{ Name="Gemini CLI";  Paths=@("$userHome\.gemini\sessions"); TsField="created_at" },
    @{ Name="GitHub Copilot"; Paths=@(Get-EditorGlobalStoragePaths -ExtensionIds @("github.copilot-chat","github.copilot")); TsField="timestamp" },
    @{ Name="Goose";       Paths=@("$userHome\.config\goose\sessions","$userHome\.local\share\goose\sessions","$userHome\.local\state\goose\logs","$appData\goose\sessions","$appData\goose\logs"); TsField="timestamp" },
    @{ Name="Hermes";      Paths=@("$userHome\.hermes\sessions","$userHome\.hermes\logs","$userHome\AppData\Roaming\Hermes\logs","$userHome\AppData\Local\Hermes\logs"); TsField="timestamp" },
    @{ Name="JetBrains AI"; Paths=@(Get-EditorGlobalStoragePaths -ExtensionIds @("JetBrains.jetbrains-ai-assistant","jetbrains.jetbrains-ai-assistant")); TsField="timestamp" },
    @{ Name="Junie";       Paths=@("$userHome\.junie\logs","$userHome\.junie\sessions"); TsField="timestamp" },
    @{ Name="Kilo Code";   Paths=@((Get-EditorGlobalStoragePaths -ExtensionIds @("kilocode.kilo-code","kilo-code.kilo-code")) + @("$userHome\.kilo","$appData\kilo")); TsField="timestamp" },
    @{ Name="opencode";    Paths=@("$userHome\.local\share\opencode\log","$userHome\.local\share\opencode","$appData\opencode\log","$appData\opencode","$userHome\.config\opencode"); TsField="timestamp" },
    @{ Name="Qwen Code";   Paths=@("$userHome\.qwen\logs\openai","$userHome\.qwen\debug","$userHome\.qwen","$userHome\.config\qwen"); TsField="timestamp" },
    @{ Name="Roo Code";    Paths=@(Get-EditorGlobalStoragePaths -ExtensionIds @("rooveterinaryinc.roo-cline","roocode.roo-cline","roo-cline.roo-cline")); TsField="timestamp" },
    @{ Name="Sourcegraph Cody"; Paths=@(Get-EditorGlobalStoragePaths -ExtensionIds @("sourcegraph.cody-ai","sourcegraph.cody")); TsField="timestamp" },
    @{ Name="Tabby";       Paths=@(Get-EditorGlobalStoragePaths -ExtensionIds @("TabbyML.vscode-tabby","tabbyml.vscode-tabby")); TsField="timestamp" },
    @{ Name="Tabnine";     Paths=@((Get-EditorGlobalStoragePaths -ExtensionIds @("TabNine.tabnine-vscode","tabnine.tabnine-vscode")) + @("$userHome\.tabnine","$appData\TabNine","$appData\Tabnine")); TsField="timestamp" },
    @{ Name="Trae";        Paths=@("$userHome\AppData\Roaming\Trae\logs","$userHome\AppData\Roaming\Trae\User\workspaceStorage","$userHome\AppData\Roaming\Trae CN\logs","$userHome\AppData\Local\Trae\logs"); TsField="timestamp" },
    @{ Name="Zed";         Paths=@("$localAppData\Zed\logs","$localAppData\Zed\conversations","$userHome\.config\zed\conversations","$userHome\.local\share\zed\conversations","$userHome\.local\share\zed\logs"); TsField="timestamp" }
)

$sourceReports = [System.Collections.Generic.List[PSCustomObject]]::new()
$sourceReportByKey = @{}

function Add-SourceReport {
    param(
        [string]$ToolName,
        [string]$Path,
        [string]$SourceType
    )
    if (-not $Path) { return $null }
    $exists = Test-Path -LiteralPath $Path
    $resolvedPath = $Path
    if ($exists) {
        try { $resolvedPath = (Resolve-Path -LiteralPath $Path).Path } catch { $resolvedPath = $Path }
    }
    $sourceKey = "$ToolName|$resolvedPath"
    if (-not $sourceReportByKey.ContainsKey($sourceKey)) {
        $report = [PSCustomObject]@{
            tool            = $ToolName
            path            = $resolvedPath
            source          = $SourceType
            detected        = [bool]$exists
            path_kind       = if ($exists) { if (Test-Path -LiteralPath $Path -PathType Leaf) { "file" } else { "directory" } } else { "missing" }
            files_scanned   = 0
            files_with_hits = 0
            raw_hits        = 0
            dedup_hits      = 0
            latest_log_at   = ""
            latest_hit_at   = ""
            status          = if ($exists) { "detected" } else { "missing" }
            status_reason   = if ($exists) { "path_detected" } else { "path_missing" }
        }
        $sourceReports.Add($report)
        $sourceReportByKey[$sourceKey] = $report
    }
    return $sourceReportByKey[$sourceKey]
}

$activeSources = [System.Collections.Generic.List[hashtable]]::new()
$activeSourceKeys = @{}
foreach ($tool in $AUTO_DETECT_TOOLS) {
    foreach ($p in $tool.Paths) {
        $report = Add-SourceReport -ToolName $tool.Name -Path $p -SourceType "auto"
        if ($report -and $report.detected) {
            $resolvedPath = $report.path
            $sourceKey = "$($tool.Name)|$resolvedPath"
            if (-not $activeSourceKeys.ContainsKey($sourceKey)) {
                $activeSources.Add(@{ Name=$tool.Name; Root=$resolvedPath; TsField=$tool.TsField })
                $activeSourceKeys[$sourceKey] = $true
                Write-Host "  [FOUND] $($tool.Name)  ->  $resolvedPath"
            }
        }
    }
}
foreach ($ct in $cfg.custom_tools) {
    if (-not $ct.path) { continue }
    $customName = if ($ct.name) { [string]$ct.name } else { "CustomTool" }
    $report = Add-SourceReport -ToolName $customName -Path ([string]$ct.path) -SourceType "custom"
    if ($report -and $report.detected) {
        $resolvedPath = $report.path
        $sourceKey = "$customName|$resolvedPath"
        if (-not $activeSourceKeys.ContainsKey($sourceKey)) {
            $activeSources.Add(@{ Name=$customName; Root=$resolvedPath; TsField="timestamp" })
            $activeSourceKeys[$sourceKey] = $true
            Write-Host "  [CUSTOM] $customName  ->  $resolvedPath"
        }
    }
}
if ($activeSources.Count -eq 0) { Write-Warning "No AI tools detected."; exit 1 }

# ── Load skill names + descriptions from SKILL.md frontmatter ─────────────────
$skillNames = @()
$skillSourcePaths = @{}
$counts = @{}
$dedupCounts = @{}
$descs  = @{}
$descRx = [System.Text.RegularExpressions.Regex]'description:\s*["'']?(.+?)["'']?\s*$'

foreach ($root in $skillRoots) {
    $skillFiles = Get-ChildItem -Path $root -Recurse -Filter "SKILL.md" -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Directory.Name -notmatch '^\.' }
    foreach ($skillFile in $skillFiles) {
        $s = $skillFile.Directory.Name
        $skillMd = $skillFile.FullName
        if (-not $counts.ContainsKey($s)) {
            $skillNames += $s
            $counts[$s] = 0
            $dedupCounts[$s] = 0
            $descs[$s] = ""
            $skillSourcePaths[$s] = $skillMd
        }
        if (-not $descs[$s]) {
            try {
                $lines = Get-Content $skillMd -TotalCount 20 -Encoding UTF8 -ErrorAction SilentlyContinue
                foreach ($ln in $lines) {
                    $m = $descRx.Match($ln)
                    if ($m.Success) { $descs[$s] = $m.Groups[1].Value.Trim('"', "'"); break }
                }
            } catch { }
        }
    }
}
$skillNames = @($skillNames | Sort-Object -Unique)
Write-Host ""
Write-Host "Tracking $($skillNames.Count) skills."
Write-Host ""

$dedupWindowMinutes = [Math]::Max(1, [int]$cfg.dedup_window_minutes)

function Get-TimeBucket {
    param(
        [string]$Timestamp,
        [datetime]$FallbackUtc,
        [int]$WindowMinutes
    )
    $dt = $FallbackUtc
    if ($Timestamp) {
        try {
            $dt = ([datetimeoffset]::Parse($Timestamp)).UtcDateTime
        } catch {
            $dt = $FallbackUtc
        }
    }
    $bucketTicks = [timespan]::FromMinutes($WindowMinutes).Ticks
    return [string]([math]::Floor($dt.Ticks / $bucketTicks))
}

function Get-StableId {
    param([string]$Value)
    if (-not $Value) { return "none" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $hash = $sha.ComputeHash($bytes)
        return -join ($hash[0..7] | ForEach-Object { $_.ToString("x2") })
    } finally {
        $sha.Dispose()
    }
}

function Get-SkillCategory {
    param([string]$Skill)
    if ($Skill -match 'academic|research|paper|citation|reviewer|pipeline|deep-research') { return 'Research' }
    if ($Skill -match 'memory|recall|remember|forget|recap|session|handoff|history') { return 'Memory' }
    if ($Skill -match 'video|audio|tts|speech|music|sound|ffmpeg|heygen|faceswap|avatar|acestep|ltx|seedance|remotion|hyperframes') { return 'Media' }
    if ($Skill -match 'threejs|svg|canvas|character|pose|lottie|gsap|framer|d3|visual|mermaid|flux|bfl|grok') { return 'Visual' }
    if ($Skill -match 'stock') { return 'Finance' }
    if ($Skill -match 'diagnose|tdd|architecture|karpathy|vercel|commit|issues|web-design|write-agentmemory|setup-matt') { return 'Engineering' }
    if ($Skill -match 'caveman|cavecrew') { return 'Compression' }
    if ($Skill -match 'agent|api|download|setup|toolkit|find-skills') { return 'Integration' }
    return 'General'
}

$catalogPath = Join-Path $cfg.output_dir "skill_catalog.json"
$existingCatalog = @{}
if (Test-Path $catalogPath) {
    try {
        $catalogItems = Get-Content $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($item in $catalogItems) {
            if ($item.skill) { $existingCatalog[$item.skill] = $item }
        }
    } catch {
        Write-Warning "Could not parse existing skill_catalog.json; translations will be regenerated as blank entries."
    }
}

# Regex: match skill path, match any known timestamp field (supports ISO and Unix epoch)
$skillRx  = [System.Text.RegularExpressions.Regex]'skills(?:[/\\]|\\\\)+([A-Za-z0-9\-_]+)(?:[/\\]|\\\\)+SKILL\.md'
$skillFileReadRx = [System.Text.RegularExpressions.Regex]'(?i)\b(Get-Content|cat|type)\b[^\r\n]*skills(?:[/\\]|\\\\)+([A-Za-z0-9\-_]+)(?:[/\\]|\\\\)+SKILL\.md'
$claudeAttributionSkillRx = [System.Text.RegularExpressions.Regex]'"attributionSkill"\s*:\s*"([^"]+)"'
$slashSkillRx = [System.Text.RegularExpressions.Regex]'/([A-Za-z0-9][A-Za-z0-9:_\-]*)(?=\s|\\r|\\n|<|$)'
$timeRx   = [System.Text.RegularExpressions.Regex]'"(?:created_at|timestamp)"\s*:\s*"([^"]+)"'
$unixRx   = [System.Text.RegularExpressions.Regex]'"ts"\s*:\s*(\d{9,13})'
$epoch    = [datetime]'1970-01-01T00:00:00Z'

$logEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
$rawSeen = @{}
$dedupSeen = @{}

function Get-ToolLogFiles {
    param(
        [string]$Root,
        [string]$ToolName
    )
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return @() }

    $broadEditorTools = @("Cline", "Roo Code", "Kilo Code", "GitHub Copilot", "Sourcegraph Cody", "Amazon Q", "Augment", "Tabby", "Tabnine")
    $jsonMdTools = @("Aider", "Amp", "Goose", "opencode", "Qwen Code", "Zed", "JetBrains AI", "Junie")
    $extensions = @(".jsonl")
    if ($ToolName -in @("Cursor", "Windsurf") -or $ToolName -in $broadEditorTools -or $ToolName -in $jsonMdTools -or $ToolName -notin @("ClaudeCode", "Codex", "Antigravity")) {
        $extensions = @(".jsonl", ".json", ".log", ".txt")
    }
    if ($ToolName -in @("Aider", "Amp", "opencode", "Qwen Code") -or $ToolName -in $broadEditorTools) {
        $extensions += ".md"
        $extensions += ".history"
    }

    if (Test-Path -LiteralPath $Root -PathType Leaf) {
        $item = Get-Item -LiteralPath $Root -ErrorAction SilentlyContinue
        if (-not $item) { return @() }
        $ext = $item.Extension.ToLowerInvariant()
        if (($extensions -contains $ext) -or ($ToolName -eq "Aider" -and $item.Name -match '^\.aider\..*history')) {
            return @($item)
        }
        return @()
    }

    $cutoffUtc = (Get-Date).ToUniversalTime().AddDays(-1 * [Math]::Max(1, $RecentDays))
    $limit = [Math]::Max(20, $RecentFiles)

    if ($ToolName -eq "Antigravity") {
        return @(Get-ChildItem -Path $Root -Recurse -Filter "transcript.jsonl" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\\.system_generated\\logs\\transcript\.jsonl$' -and $_.LastWriteTimeUtc -ge $cutoffUtc } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First $limit)
    }

    if ($ToolName -eq "Aider") {
        return @(Get-ChildItem -Path $Root -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^\.aider\..*history(\.md)?$' -or
                $_.Name -eq ".aider.chat.history.md" -or
                $_.Name -eq ".aider.llm.history"
            } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First $limit)
    }

    if ($ToolName -in @("JetBrains AI", "Junie")) {
        return @(Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                ($extensions -contains $_.Extension.ToLowerInvariant()) -and
                $_.LastWriteTimeUtc -ge $cutoffUtc -and
                ($_.FullName -match '(?i)([\\/]log[\\/]|ai-assistant|junie|matterhorn|\.junie)')
            } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First $limit)
    }

    if ($ToolName -eq "GitHub Copilot" -and $Root -match '(?i)[\\/]workspaceStorage$') {
        return @(Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                ($extensions -contains $_.Extension.ToLowerInvariant()) -and
                $_.LastWriteTimeUtc -ge $cutoffUtc -and
                ($_.FullName -match '(?i)(github\.copilot|copilot-chat|chatSessions|chatEditingSessions)')
            } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First $limit)
    }

    return @(Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $extensions -contains $_.Extension.ToLowerInvariant() -and
            $_.LastWriteTimeUtc -ge $cutoffUtc -and
            (-not ($_.Name -eq "history.jsonl" -and $ToolName -in @("ClaudeCode", "Codex", "Antigravity"))) -and
            $_.Name -ne "transcript_full.jsonl"
        } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First $limit)
}

function Test-GeneratedSkillInventoryLine {
    param([string]$Line)
    return (
        $Line.Contains('<skills_instructions>') -or
        $Line.Contains('### Available skills') -or
        $Line.Contains('### Skill roots') -or
        $Line.Contains('"type":"skill_listing"')
    )
}

function Test-ExplicitSkillCommandLine {
    param([string]$Line)
    return (
        $Line.Contains('<command-name>/') -or
        $Line.Contains('<USER_REQUEST>') -or
        $Line.Contains('"source":"USER_EXPLICIT"') -or
        $Line.Contains('"type":"USER_INPUT"')
    )
}

function Test-SkillReadLine {
    param([string]$Line)
    if (-not $Line.Contains('SKILL.md')) { return $false }
    if ($Line.Contains('"type":"function_call_output"')) { return $false }
    if ($Line.Contains('[external_agent_tool_result]')) { return $false }
    if ($Line.Contains('"type":"GREP_SEARCH"')) { return $false }
    if ($Line.Contains('"type":"RUN_COMMAND"')) { return $false }
    if ($Line.Contains('Skills 清单') -or $Line.Contains('已下载的 Skills')) { return $false }

    return (
        $Line.Contains('[external_agent_tool_call: Read]') -or
        $Line.Contains('"type":"VIEW_FILE"') -or
        $Line.Contains('"name":"Read"') -or
        $Line.Contains('"name":"view_file"') -or
        ($Line -match '(?i)\b(Get-Content|cat)\b[^\r\n]*SKILL\.md')
    )
}

# ── Watch Loop Setup ───────────────────────────────────────────────────────────
$fileStates = @{}

$pidPath = Join-Path $cfg.output_dir ".collector.pid"
if ($Watch) {
    [System.IO.File]::WriteAllText($pidPath, $pid, [System.Text.Encoding]::UTF8)
}

function Get-LogFilesState {
    $state = @{}
    foreach ($src in $activeSources) {
        $files = Get-ToolLogFiles -Root $src.Root -ToolName $src.Name
        foreach ($f in $files) {
            $state[$f.FullName] = @{
                LastWriteTimeUtc = $f.LastWriteTimeUtc
                Length           = $f.Length
            }
        }
    }
    return $state
}

$global:fileCache = @{}
$firstRun = $true

try {
    while ($true) {
    if ($Watch) {
        $currentState = Get-LogFilesState
        $changed = $false

        if ($firstRun) {
            $changed = $true
            $firstRun = $false
        } else {
            # Check for additions or modifications
            foreach ($key in $currentState.Keys) {
                if (-not $fileStates.ContainsKey($key)) {
                    $changed = $true
                    break
                } else {
                    $old = $fileStates[$key]
                    $new = $currentState[$key]
                    if ($old.LastWriteTimeUtc -ne $new.LastWriteTimeUtc -or $old.Length -ne $new.Length) {
                        $changed = $true
                        break
                    }
                }
            }
            # Check for deletions
            if (-not $changed) {
                foreach ($key in $fileStates.Keys) {
                    if (-not $currentState.ContainsKey($key)) {
                        $changed = $true
                        break
                    }
                }
            }
        }

        if (-not $changed) {
            Start-Sleep -Seconds 5
            continue
        }

        $fileStates = $currentState
        $nowStr = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$nowStr] Log files updated. Re-scanning..."
    }

    # Reset accumulator variables for clean scan
    foreach ($key in $counts.Keys | Get-Unique) {
        $counts[$key] = 0
        $dedupCounts[$key] = 0
    }
    $logEntries.Clear()
    $rawSeen.Clear()
    $dedupSeen.Clear()

# ── Scan each tool ─────────────────────────────────────────────────────────────
foreach ($src in $activeSources) {
    $root     = $src.Root
    $toolName = $src.Name
    $files = Get-ToolLogFiles -Root $root -ToolName $toolName
    $hits = 0
    $dedupHits = 0
    $sourceKey = "$toolName|$root"
    $sourceReport = $sourceReportByKey[$sourceKey]
    if ($sourceReport) {
        $sourceReport.files_scanned = $files.Count
        $sourceReport.files_with_hits = 0
        $latestLogTimeUtc = $null
        if ($files.Count -gt 0) {
            $latestLogTimeUtc = ($files | Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum
        }
        $sourceReport.latest_log_at = if ($latestLogTimeUtc) { ([datetime]$latestLogTimeUtc).ToString("yyyy-MM-ddTHH:mm:ssZ") } else { "" }
        $sourceReport.status = if ($files.Count -gt 0) { "scanned" } else { "no_log_files" }
        $sourceReport.status_reason = if ($files.Count -gt 0) { "log_files_detected" } else { "path_detected_but_no_log_files" }
    }
    Write-Host "Scanning $toolName  ($($files.Count) files)..."

    foreach ($f in $files) {
        $sessionId = ''
        $fileHitCount = 0
        $fileLatestHitUtc = $null
        if ($f.FullName -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
            $sessionId = $Matches[1]
        }

        # Query Cache
        $cacheKey = $f.FullName
        $cacheEntry = $global:fileCache[$cacheKey]
        $rawHits = @()
        if ($cacheEntry -and $cacheEntry.LastWriteTimeUtc -eq $f.LastWriteTimeUtc -and $cacheEntry.Length -eq $f.Length) {
            $rawHits = $cacheEntry.RawHits
        } else {
            $fs = $null
            $sr = $null
            try {
                $fs = [System.IO.FileStream]::new(
                    $f.FullName,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
                )
                $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
                while (-not $sr.EndOfStream) {
                    $line = $sr.ReadLine()
                    if (-not $line) { continue }
                    if (Test-GeneratedSkillInventoryLine $line) { continue }
                    $lineSkills = [System.Collections.Generic.List[string]]::new()

                    if ($line.Contains('SKILL.md') -and
                        -not $line.Contains('"type":"function_call_output"') -and
                        -not $line.Contains('[external_agent_tool_result]') -and
                        -not $line.Contains('"type":"GREP_SEARCH"') -and
                        -not $line.Contains('"type":"RUN_COMMAND"')) {
                        foreach ($m in $skillFileReadRx.Matches($line)) {
                            [void]$lineSkills.Add($m.Groups[2].Value)
                        }
                        foreach ($m in $skillRx.Matches($line)) {
                            [void]$lineSkills.Add($m.Groups[1].Value)
                        }
                    }

                    # Claude Code exposes an explicit attribution field. Other tools are
                    # counted only from explicit slash invocations or real skill-file reads.
                    if ($line.Contains('"attributionSkill"')) {
                        foreach ($m in $claudeAttributionSkillRx.Matches($line)) {
                            [void]$lineSkills.Add($m.Groups[1].Value)
                        }
                    }

                    if (Test-ExplicitSkillCommandLine $line) {
                        foreach ($m in $slashSkillRx.Matches($line)) {
                            [void]$lineSkills.Add($m.Groups[1].Value)
                        }
                    }

                    if (Test-SkillReadLine $line) {
                        foreach ($m in $skillFileReadRx.Matches($line)) {
                            [void]$lineSkills.Add($m.Groups[2].Value)
                        }
                        foreach ($m in $skillRx.Matches($line)) {
                            [void]$lineSkills.Add($m.Groups[1].Value)
                        }
                    }

                    if ($lineSkills.Count -eq 0) { continue }

                    # Extract timestamp (ISO string first, then Unix epoch)
                    $ts = ''
                    $tm = $timeRx.Match($line)
                    if ($tm.Success) {
                        $ts = $tm.Groups[1].Value
                    } else {
                        $um = $unixRx.Match($line)
                        if ($um.Success) {
                            $unixMs = [long]$um.Groups[1].Value
                            # If > 1e11 treat as milliseconds, otherwise seconds
                            if ($unixMs -gt 100000000000) { $unixMs = [long]($unixMs / 1000) }
                            $ts = $epoch.AddSeconds($unixMs).ToString("yyyy-MM-ddTHH:mm:ssZ")
                        }
                    }

                    $lineHash = Get-StableId $line
                    foreach ($skill in @($lineSkills | Select-Object -Unique)) {
                        $rawHits += [PSCustomObject]@{
                            skill    = $skill
                            ts       = $ts
                            lineHash = $lineHash
                        }
                    }
                }
            } catch { } finally {
                if ($sr) { $sr.Close() }
                elseif ($fs) { $fs.Close() }
            }
            $global:fileCache[$cacheKey] = @{
                LastWriteTimeUtc = $f.LastWriteTimeUtc
                Length           = $f.Length
                RawHits          = $rawHits
            }
        }

        # Process accumulated or cached raw hits
        foreach ($hit in $rawHits) {
            $skill = $hit.skill
            if ($counts.ContainsKey($skill)) {
                $ts = $hit.ts
                $sessionKey = if ($sessionId) { "session:$sessionId" } else { "file:$(Get-StableId $f.FullName)" }
                $rawKeyTime = if ($ts) { $ts } else { "line:$($hit.lineHash)" }
                $rawKey = "$toolName|$sessionKey|$skill|$rawKeyTime"
                if ($rawSeen.ContainsKey($rawKey)) { continue }
                $rawSeen[$rawKey] = $true

                $counts[$skill]++
                $bucket = Get-TimeBucket -Timestamp $ts -FallbackUtc $f.LastWriteTimeUtc -WindowMinutes $dedupWindowMinutes
                $dedupKey = "$toolName|$sessionKey|$skill|$bucket"
                $isDedupedCall = -not $dedupSeen.ContainsKey($dedupKey)
                if ($isDedupedCall) {
                    $dedupSeen[$dedupKey] = $true
                    $dedupCounts[$skill]++
                    $dedupHits++
                }
                $logEntries.Add([PSCustomObject]@{
                    skill     = $skill
                    tool      = $toolName
                    time      = if ($ts) { $ts } else { $f.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ") }
                    session   = $sessionId
                    dedup     = $isDedupedCall
                    dedup_key = $dedupKey
                })
                $hits++
                $fileHitCount++
                $hitUtc = $f.LastWriteTimeUtc
                if ($ts) {
                    try { $hitUtc = ([datetimeoffset]::Parse($ts)).UtcDateTime } catch { $hitUtc = $f.LastWriteTimeUtc }
                }
                if (-not $fileLatestHitUtc -or $hitUtc -gt $fileLatestHitUtc) {
                    $fileLatestHitUtc = $hitUtc
                }
            }
        }

        if ($sourceReport -and $fileHitCount -gt 0) {
            $sourceReport.files_with_hits++
            if ($fileLatestHitUtc) {
                $latestSourceHitUtc = $null
                if ($sourceReport.latest_hit_at) {
                    try { $latestSourceHitUtc = ([datetimeoffset]::Parse($sourceReport.latest_hit_at)).UtcDateTime } catch { $latestSourceHitUtc = $null }
                }
                if (-not $latestSourceHitUtc -or $fileLatestHitUtc -gt $latestSourceHitUtc) {
                    $sourceReport.latest_hit_at = $fileLatestHitUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
            }
        }
    }
    if ($sourceReport) {
        $sourceReport.raw_hits = $hits
        $sourceReport.dedup_hits = $dedupHits
        if ($files.Count -gt 0) {
            $sourceReport.status = if ($hits -gt 0) { "ok" } else { "no_skill_hits" }
            $sourceReport.status_reason = if ($hits -gt 0) { "skill_hits_detected" } else { "log_files_scanned_but_no_skill_hits" }
        }
    }
    Write-Host "  -> $hits hits"
}

# ── Output JSON ────────────────────────────────────────────────────────────────
$catalogArr = @()
$arr = @()
foreach ($kv in $counts.GetEnumerator() | Sort-Object Name) {
    $skill = $kv.Key
    $existing = $existingCatalog[$skill]
    $category = Get-SkillCategory $skill
    $zhDesc = if ($existing -and $existing.zh_desc) { $existing.zh_desc } else { "" }
    $sourcePath = if ($skillSourcePaths.ContainsKey($skill)) { $skillSourcePaths[$skill] } else { "" }

    $catalogItem = [PSCustomObject]@{
        skill        = $skill
        category     = $category
        zh_desc      = $zhDesc
        english_desc = $descs[$skill]
        triggers     = if ($existing -and $existing.triggers) { $existing.triggers } else { @() }
        source_path  = $sourcePath
    }
    $catalogArr += $catalogItem

    $arr += [PSCustomObject]@{
        skill       = $skill
        count       = $dedupCounts[$skill]
        dedup_count = $dedupCounts[$skill]
        raw_count   = $counts[$skill]
        desc        = $descs[$skill]
        category    = $category
        zh_desc     = $zhDesc
    }
}
$genAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$buildId = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$detectedTools = @($activeSources | ForEach-Object { [string]$_.Name } | Sort-Object -Unique)
$jsonObj = [PSCustomObject]@{
    skill_call_stats = $arr
    generated_at     = $genAt
    build_id         = $buildId
    tools_detected   = $detectedTools
    dedup_window_minutes = $dedupWindowMinutes
}
$jsonPath = Join-Path $cfg.output_dir "skill_call_stats.json"
[System.IO.File]::WriteAllText($jsonPath, ($jsonObj | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText($catalogPath, ($catalogArr | ConvertTo-Json -Depth 8), [System.Text.Encoding]::UTF8)
$catalogJsPath = Join-Path $cfg.output_dir "skill_catalog.js"
$catalogJson = @($catalogArr) | ConvertTo-Json -Depth 8 -Compress
[System.IO.File]::WriteAllText($catalogJsPath, "var SKILL_CATALOG = $catalogJson;`n", [System.Text.Encoding]::UTF8)

# ── Output skill_data.js ───────────────────────────────────────────────────────
$sb = [System.Text.StringBuilder]::new()
$skillDataJson = @($arr) | ConvertTo-Json -Depth 6 -Compress
$detectedToolsJson = ConvertTo-Json -InputObject $detectedTools -Depth 3 -Compress
[void]$sb.AppendLine("var SKILL_DATA = $skillDataJson;")
[void]$sb.AppendLine("var GENERATED_AT = `"$genAt`";")
[void]$sb.AppendLine("var BUILD_ID = $buildId;")
[void]$sb.AppendLine("var DEDUP_WINDOW_MINUTES = $dedupWindowMinutes;")
[void]$sb.AppendLine("var DETECTED_TOOLS = $detectedToolsJson;")
$jsPath = Join-Path $cfg.output_dir "skill_data.js"
[System.IO.File]::WriteAllText($jsPath, $sb.ToString(), [System.Text.Encoding]::UTF8)

# ── Output skill_log.js ────────────────────────────────────────────────────────
$maxE  = [Math]::Max(1, [int]$cfg.max_log_entries)
$sorted = $logEntries | Sort-Object { $_.time } -Descending | Select-Object -First $maxE
$lb = [System.Text.StringBuilder]::new()
$logJson = @($sorted) | ConvertTo-Json -Depth 6 -Compress
[void]$lb.AppendLine("var SKILL_LOG = $logJson;")
[void]$lb.AppendLine("var BUILD_ID = $buildId;")
$logPath = Join-Path $cfg.output_dir "skill_log.js"
[System.IO.File]::WriteAllText($logPath, $lb.ToString(), [System.Text.Encoding]::UTF8)

# ── Output tool source coverage report ────────────────────────────────────────
$toolReports = @($sourceReports | Sort-Object tool, path)
$supportedToolNames = @($AUTO_DETECT_TOOLS | ForEach-Object { $_.Name } | Sort-Object -Unique)
$toolSummaries = @()
foreach ($toolName in $supportedToolNames) {
    $rows = @($toolReports | Where-Object { $_.tool -eq $toolName })
    $detectedRows = @($rows | Where-Object { $_.detected })
    $files = [int](($detectedRows | Measure-Object files_scanned -Sum).Sum)
    $filesWithHits = [int](($detectedRows | Measure-Object files_with_hits -Sum).Sum)
    $raw = [int](($detectedRows | Measure-Object raw_hits -Sum).Sum)
    $dedup = [int](($detectedRows | Measure-Object dedup_hits -Sum).Sum)
    $status = "missing"
    if ($detectedRows.Count -gt 0) {
        if ($raw -gt 0) {
            $status = "ok"
        } elseif ($files -gt 0) {
            $status = "no_skill_hits"
        } else {
            $status = "no_log_files"
        }
    }
    $latestHitAt = @($detectedRows | Where-Object { $_.latest_hit_at } | Select-Object -ExpandProperty latest_hit_at | Sort-Object -Descending | Select-Object -First 1)
    $latestLogAt = @($detectedRows | Where-Object { $_.latest_log_at } | Select-Object -ExpandProperty latest_log_at | Sort-Object -Descending | Select-Object -First 1)
    $toolSummaries += [PSCustomObject]@{
        tool            = $toolName
        status          = $status
        source_count    = $detectedRows.Count
        files_scanned   = $files
        files_with_hits = $filesWithHits
        raw_hits        = $raw
        dedup_hits      = $dedup
        latest_log_at   = if ($latestLogAt) { [string]$latestLogAt[0] } else { "" }
        latest_hit_at   = if ($latestHitAt) { [string]$latestHitAt[0] } else { "" }
    }
}
$statusCounts = [ordered]@{
    ok            = @($toolSummaries | Where-Object { $_.status -eq "ok" }).Count
    no_skill_hits = @($toolSummaries | Where-Object { $_.status -eq "no_skill_hits" }).Count
    no_log_files  = @($toolSummaries | Where-Object { $_.status -eq "no_log_files" }).Count
    missing       = @($toolSummaries | Where-Object { $_.status -eq "missing" }).Count
}
$toolReportObj = [PSCustomObject]@{
    generated_at = $genAt
    build_id = $buildId
    summary = [PSCustomObject]@{
        supported_tools       = $supportedToolNames
        skill_roots           = @($skillRoots)
        detected_source_count = @($toolReports | Where-Object { $_.detected }).Count
        scanned_file_count    = [int](($toolReports | Measure-Object files_scanned -Sum).Sum)
        raw_hits              = [int](($toolReports | Measure-Object raw_hits -Sum).Sum)
        dedup_hits            = [int](($toolReports | Measure-Object dedup_hits -Sum).Sum)
        status_counts         = [PSCustomObject]$statusCounts
    }
    tools = $toolSummaries
    sources = $toolReports
}
$toolReportJsonPath = Join-Path $cfg.output_dir "tool_report.json"
[System.IO.File]::WriteAllText($toolReportJsonPath, ($toolReportObj | ConvertTo-Json -Depth 8), [System.Text.Encoding]::UTF8)
$toolReportJsPath = Join-Path $cfg.output_dir "tool_report.js"
$toolReportJson = $toolReportObj | ConvertTo-Json -Depth 8 -Compress
[System.IO.File]::WriteAllText($toolReportJsPath, "var TOOL_REPORT = $toolReportJson;`nvar BUILD_ID = $buildId;`n", [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "=== Done === Total entries: $($logEntries.Count)"
Write-Host "  JS  -> $jsPath"
Write-Host "  LOG -> $logPath"
Write-Host "  TOOLS -> $toolReportJsonPath"
Write-Host ""
Write-Host "=== Top 10 ==="
$arr | Sort-Object count -Descending | Select-Object -First 10 |
    ForEach-Object { Write-Host "  $($_.skill): $($_.count)" }

    if (-not $Watch) {
        break
    }
    Write-Host "Watching for changes... (Press Ctrl+C to stop)"
    Start-Sleep -Seconds 5
}
} finally {
    if ($Watch -and (Test-Path $pidPath)) {
        Remove-Item $pidPath -Force -ErrorAction SilentlyContinue
    }
}
