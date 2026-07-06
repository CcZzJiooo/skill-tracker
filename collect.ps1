<#
.SYNOPSIS
  Skill Tracker — collect AI skill call logs across all AI coding tools.
#>
param(
    [string]$SkillsRoot = "",
    [string]$ConfigFile = "$PSScriptRoot\config.json",
    [string]$OutputDir  = ""
)

# ── Load config ────────────────────────────────────────────────────────────────
$cfg = @{ skills_root=""; output_dir="./dashboard"; max_log_entries=5000; dedup_window_minutes=2; custom_tools=@() }
if (Test-Path $ConfigFile) {
    try {
        $raw = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        if ($raw.skills_root)     { $cfg.skills_root     = $raw.skills_root }
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

# ── Auto-detect skills root ────────────────────────────────────────────────────
$userHome = $env:USERPROFILE
if (-not $cfg.skills_root) {
    foreach ($c in @(
        "$userHome\.codex\skills",
        "$userHome\.agents\skills",
        "$userHome\.claude\skills",
        "$userHome\.gemini\config\skills",
        "$userHome\.config\gemini\skills",
        "$userHome\.cc-switch\skills"
    )) {
        if (Test-Path $c) { $cfg.skills_root = $c; break }
    }
}
if (-not $cfg.skills_root -or -not (Test-Path $cfg.skills_root)) {
    Write-Error "Cannot find skills directory. Set 'skills_root' in config.json."
    exit 1
}
Write-Host "Skills root: $($cfg.skills_root)"

# ── Auto-detect installed AI tools ────────────────────────────────────────────
# Each tool specifies: Name, one or more scan roots, and a timestamp field preference
$AUTO_DETECT_TOOLS = @(
    @{ Name="Antigravity"; Paths=@("$userHome\.gemini\antigravity-ide\brain"); TsField="created_at" },
    @{ Name="ClaudeCode";  Paths=@("$userHome\.claude\projects"); TsField="timestamp" },
    @{ Name="Codex";       Paths=@("$userHome\.codex\archived_sessions","$userHome\.codex\sessions"); TsField="timestamp" },
    @{ Name="Cursor";      Paths=@("$userHome\.cursor\logs","$userHome\AppData\Roaming\Cursor\logs"); TsField="timestamp" },
    @{ Name="Windsurf";    Paths=@("$userHome\.codeium\windsurf\logs","$userHome\AppData\Roaming\Windsurf\logs"); TsField="timestamp" },
    @{ Name="Continue";    Paths=@("$userHome\.continue\sessions"); TsField="timestamp" },
    @{ Name="Gemini CLI";  Paths=@("$userHome\.gemini\sessions"); TsField="created_at" }
)

$activeSources = [System.Collections.Generic.List[hashtable]]::new()
foreach ($tool in $AUTO_DETECT_TOOLS) {
    foreach ($p in $tool.Paths) {
        if (Test-Path $p) {
            $activeSources.Add(@{ Name=$tool.Name; Root=$p; TsField=$tool.TsField })
            Write-Host "  [FOUND] $($tool.Name)  ->  $p"
            break
        }
    }
}
foreach ($ct in $cfg.custom_tools) {
    if ($ct.path -and (Test-Path $ct.path)) {
        $activeSources.Add(@{ Name=$ct.name; Root=$ct.path; TsField="timestamp" })
        Write-Host "  [CUSTOM] $($ct.name)  ->  $($ct.path)"
    }
}
if ($activeSources.Count -eq 0) { Write-Warning "No AI tools detected."; exit 1 }

# ── Load skill names + descriptions from SKILL.md frontmatter ─────────────────
$skillNames = Get-ChildItem -Path $cfg.skills_root -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -notmatch '^\.' } |
              Select-Object -ExpandProperty Name
$counts = @{}
$dedupCounts = @{}
$descs  = @{}
$descRx = [System.Text.RegularExpressions.Regex]'description:\s*["'']?(.+?)["'']?\s*$'

foreach ($s in $skillNames) {
    $counts[$s] = 0
    $dedupCounts[$s] = 0
    $descs[$s]  = ""
    $skillMd = Join-Path $cfg.skills_root "$s\SKILL.md"
    if (Test-Path $skillMd) {
        try {
            $lines = Get-Content $skillMd -TotalCount 20 -Encoding UTF8 -ErrorAction SilentlyContinue
            foreach ($ln in $lines) {
                $m = $descRx.Match($ln)
                if ($m.Success) { $descs[$s] = $m.Groups[1].Value.Trim('"', "'"); break }
            }
        } catch { }
    }
}
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
$skillRx  = [System.Text.RegularExpressions.Regex]'skills[/\\]+([A-Za-z0-9\-_]+)[/\\]+SKILL\.md'
$timeRx   = [System.Text.RegularExpressions.Regex]'"(?:created_at|timestamp)"\s*:\s*"([^"]+)"'
$unixRx   = [System.Text.RegularExpressions.Regex]'"ts"\s*:\s*(\d{9,13})'
$epoch    = [datetime]'1970-01-01T00:00:00Z'

$logEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
$dedupSeen = @{}

# ── Scan each tool ─────────────────────────────────────────────────────────────
foreach ($src in $activeSources) {
    $root     = $src.Root
    $toolName = $src.Name
    # For Codex: prefer archived_sessions, skip history.jsonl (it's a prompt history, not session)
    $files = Get-ChildItem -Path $root -Recurse -Filter "*.jsonl" -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -ne "history.jsonl" }
    $hits = 0
    Write-Host "Scanning $toolName  ($($files.Count) files)..."

    foreach ($f in $files) {
        $sessionId = ''
        if ($f.FullName -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
            $sessionId = $Matches[1]
        }
        try {
            $sr = [System.IO.StreamReader]::new($f.FullName, [System.Text.Encoding]::UTF8)
            while (-not $sr.EndOfStream) {
                $line = $sr.ReadLine()
                if (-not $line -or -not $line.Contains('SKILL.md')) { continue }

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

                $ms = $skillRx.Matches($line)
                foreach ($m in $ms) {
                    $skill = $m.Groups[1].Value
                    if ($counts.ContainsKey($skill)) {
                        $counts[$skill]++
                        $sessionKey = if ($sessionId) { "session:$sessionId" } else { "file:$(Get-StableId $f.FullName)" }
                        $bucket = Get-TimeBucket -Timestamp $ts -FallbackUtc $f.LastWriteTimeUtc -WindowMinutes $dedupWindowMinutes
                        $dedupKey = "$toolName|$sessionKey|$skill|$bucket"
                        $isDedupedCall = -not $dedupSeen.ContainsKey($dedupKey)
                        if ($isDedupedCall) {
                            $dedupSeen[$dedupKey] = $true
                            $dedupCounts[$skill]++
                        }
                        $logEntries.Add([PSCustomObject]@{
                            skill     = $skill
                            tool      = $toolName
                            time      = $ts
                            session   = $sessionId
                            dedup     = $isDedupedCall
                            dedup_key = $dedupKey
                        })
                        $hits++
                    }
                }
            }
            $sr.Close()
        } catch { }
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
    $sourcePath = Join-Path $cfg.skills_root "$skill\SKILL.md"

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
$jsonObj = [PSCustomObject]@{
    skill_call_stats = $arr
    generated_at     = $genAt
    tools_detected   = ($activeSources | ForEach-Object { $_.Name })
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
$detectedTools = @($activeSources | ForEach-Object { [string]$_.Name })
$detectedToolsJson = ConvertTo-Json -InputObject $detectedTools -Depth 3 -Compress
[void]$sb.AppendLine("var SKILL_DATA = $skillDataJson;")
[void]$sb.AppendLine("var GENERATED_AT = `"$genAt`";")
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
$logPath = Join-Path $cfg.output_dir "skill_log.js"
[System.IO.File]::WriteAllText($logPath, $lb.ToString(), [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "=== Done === Total entries: $($logEntries.Count)"
Write-Host "  JS  -> $jsPath"
Write-Host "  LOG -> $logPath"
Write-Host ""
Write-Host "=== Top 10 ==="
$arr | Sort-Object count -Descending | Select-Object -First 10 |
    ForEach-Object { Write-Host "  $($_.skill): $($_.count)" }
