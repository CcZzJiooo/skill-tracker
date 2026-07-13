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
    Write-Warning "No skills directory was found. Only calls backed by a local SKILL.md can be emitted, so the catalog may remain empty."
} else {
    Write-Host "Skills roots:"
    foreach ($root in $skillRoots) { Write-Host "  $root" }
}

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
if ($activeSources.Count -eq 0) {
    Write-Warning "No AI tools detected. Writing an empty local scan report."
}

# ── Load SKILL.md metadata and bounded semantic context ───────────────────────
function ConvertTo-NormalizedSkillText {
    param([string]$Text)

    if ($null -eq $Text) { return "" }
    $value = [string]$Text
    $value = $value -replace '^\uFEFF', ''
    $value = $value -replace "[`r`n`t]+", ' '
    $value = $value -replace '\s+', ' '
    return $value.Trim()
}

function Get-FrontmatterField {
    param(
        [string[]]$Lines,
        [string]$Name
    )

    $pattern = '^(?<indent>\s*)' + [regex]::Escape($Name) + '\s*:\s*(?<value>.*)$'
    for ($index = 0; $index -lt $Lines.Count; $index += 1) {
        $match = [regex]::Match([string]$Lines[$index], $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            return [PSCustomObject]@{
                index  = $index
                indent = $match.Groups['indent'].Value.Length
                value  = $match.Groups['value'].Value.Trim()
            }
        }
    }
    return $null
}

function Get-FrontmatterText {
    param(
        [string[]]$Lines,
        [string]$Name
    )

    $field = Get-FrontmatterField -Lines $Lines -Name $Name
    if ($null -eq $field) { return "" }
    $value = [string]$field.value
    if ($value -match '^[>|][+-]?$') {
        $parts = [System.Collections.Generic.List[string]]::new()
        for ($index = [int]$field.index + 1; $index -lt $Lines.Count; $index += 1) {
            $line = [string]$Lines[$index]
            if (-not $line.Trim()) { continue }
            $indent = $line.Length - $line.TrimStart().Length
            if ($indent -le [int]$field.indent) { break }
            [void]$parts.Add($line.Trim())
        }
        return ConvertTo-NormalizedSkillText -Text ($parts -join ' ')
    }
    if ($value.Length -ge 2 -and (
        ($value.StartsWith('"') -and $value.EndsWith('"')) -or
        ($value.StartsWith("'") -and $value.EndsWith("'"))
    )) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    return ConvertTo-NormalizedSkillText -Text $value
}

function Get-FrontmatterList {
    param(
        [string[]]$Lines,
        [string]$Name
    )

    $field = Get-FrontmatterField -Lines $Lines -Name $Name
    if ($null -eq $field) { return @() }
    $values = [System.Collections.Generic.List[string]]::new()
    $value = [string]$field.value
    if ($value.StartsWith('[') -and $value.EndsWith(']') -and $value.Length -ge 2) {
        foreach ($piece in ($value.Substring(1, $value.Length - 2) -split ',')) {
            $normalized = ConvertTo-NormalizedSkillText -Text $piece.Trim(' ', '"', "'")
            if ($normalized) { [void]$values.Add($normalized) }
        }
    } elseif ($value) {
        $normalized = ConvertTo-NormalizedSkillText -Text $value.Trim(' ', '"', "'")
        if ($normalized) { [void]$values.Add($normalized) }
    } else {
        for ($index = [int]$field.index + 1; $index -lt $Lines.Count; $index += 1) {
            $line = [string]$Lines[$index]
            if (-not $line.Trim()) { continue }
            $indent = $line.Length - $line.TrimStart().Length
            if ($indent -le [int]$field.indent) { break }
            $itemMatch = [regex]::Match($line.Trim(), '^[-*]\s*(?<item>.+)$')
            if (-not $itemMatch.Success) { continue }
            $normalized = ConvertTo-NormalizedSkillText -Text $itemMatch.Groups['item'].Value.Trim(' ', '"', "'")
            if ($normalized -and -not $values.Contains($normalized)) { [void]$values.Add($normalized) }
        }
    }
    return @($values)
}

function Get-SkillDocumentMetadata {
    param([string]$Path)

    $metadata = [PSCustomObject]@{
        description    = ""
        zh_description = ""
        triggers       = @()
        body_excerpt   = ""
    }
    try {
        $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        $body = $content
        $frontMatch = [regex]::Match($content, '(?s)\A\uFEFF?---[ \t]*\r?\n(?<front>.*?)\r?\n---[ \t]*(?:\r?\n|$)')
        if ($frontMatch.Success) {
            $frontLines = @($frontMatch.Groups['front'].Value -split "`r?`n")
            $metadata.description = Get-FrontmatterText -Lines $frontLines -Name 'description'
            if (-not $metadata.description) {
                $metadata.description = Get-FrontmatterText -Lines $frontLines -Name 'summary'
            }
            $metadata.zh_description = Get-FrontmatterText -Lines $frontLines -Name 'description_zh'
            if (-not $metadata.zh_description) {
                $metadata.zh_description = Get-FrontmatterText -Lines $frontLines -Name 'zh_desc'
            }
            if (-not $metadata.zh_description -and $metadata.description -match '^\s*[\p{IsCJKUnifiedIdeographs}]') {
                $metadata.zh_description = $metadata.description
            }
            $metadata.triggers = Get-FrontmatterList -Lines $frontLines -Name 'triggers'
            $body = $content.Substring($frontMatch.Index + $frontMatch.Length)
        }
        $body = $body -replace '(?s)```.*?```', ' '
        $body = $body -replace '(?m)^\s{0,3}#{1,6}\s*', ''
        $body = ConvertTo-NormalizedSkillText -Text $body
        if ($body.Length -gt 1800) { $body = $body.Substring(0, 1800) }
        $metadata.body_excerpt = $body
    } catch {
        Write-Warning "Could not read SKILL.md metadata: $Path"
    }
    return $metadata
}

$skillNames = @()
$skillSourcePaths = @{}
$skillMetadata = @{}
$counts = @{}
$dedupCounts = @{}
$descs = @{}

foreach ($root in $skillRoots) {
    $skillFiles = Get-ChildItem -Path $root -Recurse -Filter "SKILL.md" -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.FullName.Substring($root.Length) -notmatch '[\\/]\.[^\\/]' }
    foreach ($skillFile in $skillFiles) {
        $s = $skillFile.Directory.Name
        $skillMd = $skillFile.FullName
        $metadata = Get-SkillDocumentMetadata -Path $skillMd
        if (-not $counts.ContainsKey($s)) {
            $skillNames += $s
            $counts[$s] = 0
            $dedupCounts[$s] = 0
            $descs[$s] = ""
            $skillSourcePaths[$s] = $skillMd
            $skillMetadata[$s] = $metadata
        } elseif ((-not $skillMetadata[$s].description) -and $metadata.description) {
            $skillMetadata[$s] = $metadata
            $skillSourcePaths[$s] = $skillMd
        }
        if (-not $descs[$s] -and $metadata.description) {
            $descs[$s] = $metadata.description
        }
    }
}
$skillNames = @($skillNames | Sort-Object -Unique)

function Update-SkillInventory {
    foreach ($root in $skillRoots) {
        $skillFiles = Get-ChildItem -Path $root -Recurse -Filter "SKILL.md" -File -ErrorAction SilentlyContinue |
                      Where-Object { $_.FullName.Substring($root.Length) -notmatch '[\\/]\.[^\\/]' }
        foreach ($skillFile in $skillFiles) {
            $skill = $skillFile.Directory.Name
            $skillMd = $skillFile.FullName
            $metadata = Get-SkillDocumentMetadata -Path $skillMd
            if (-not $script:counts.ContainsKey($skill)) {
                $script:skillNames += $skill
                $script:counts[$skill] = 0
                $script:dedupCounts[$skill] = 0
                $script:descs[$skill] = [string]$metadata.description
                $script:skillSourcePaths[$skill] = $skillMd
                $script:skillMetadata[$skill] = $metadata
                continue
            }

            $currentPath = if ($script:skillSourcePaths.ContainsKey($skill)) { [string]$script:skillSourcePaths[$skill] } else { "" }
            if ($currentPath -eq $skillMd -or -not $script:skillMetadata.ContainsKey($skill) -or -not $script:skillMetadata[$skill].description) {
                $script:skillSourcePaths[$skill] = $skillMd
                $script:skillMetadata[$skill] = $metadata
                $script:descs[$skill] = [string]$metadata.description
            }
        }
    }
    $script:skillNames = @($script:skillNames | Sort-Object -Unique)
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

$translationVersion = "local-semantic-v5"
$categoryLabels = @{
    Research    = "研究与学术写作"
    Memory      = "记忆与上下文管理"
    Media       = "音视频与媒体处理"
    Visual      = "视觉与前端开发"
    Finance     = "金融与市场分析"
    Engineering = "工程开发"
    Compression = "提示词压缩"
    Integration = "工具与服务集成"
    General     = "通用自动化"
}
$skillSemanticRules = @(
    @{ pattern = '(?i)\bwebflow\b'; label = 'Webflow' },
    @{ pattern = '(?i)\bthree\.?js\b|\bthreejs\b'; label = 'Three.js' },
    @{ pattern = '(?i)\breact\b'; label = 'React' },
    @{ pattern = '(?i)\bnext\.?js\b'; label = 'Next.js' },
    @{ pattern = '(?i)\bgsap\b|scrolltrigger'; label = 'GSAP 动效' },
    @{ pattern = '(?i)framer\s+motion'; label = 'Framer Motion' },
    @{ pattern = '(?i)tailwind'; label = 'Tailwind CSS' },
    @{ pattern = '(?i)frontend|front-end|user interface|\bui\b|\bux\b'; label = '前端界面' },
    @{ pattern = '(?i)\bdesign\b|fonts?|spacing|shadows?|card structures?|visual design|design system|brand|typography|\blayout\b|bento'; label = '视觉设计与排版' },
    @{ pattern = '(?i)accessibility|\ba11y\b|\bwcag\b'; label = '可访问性' },
    @{ pattern = '(?i)responsive|mobile'; label = '响应式布局' },
    @{ pattern = '(?i)animation|motion|scroll'; label = '动效与交互' },
    @{ pattern = '(?i)performance|optimi[sz]'; label = '性能优化' },
    @{ pattern = '(?i)\bapi\b|\bmcp\b|\bsdk\b|\bhttp\b|webhook'; label = 'API 与工具集成' },
    @{ pattern = '(?i)deploy|deployment|ci/cd|publish'; label = '部署与发布' },
    @{ pattern = '(?i)\btest\b|testing|\btdd\b'; label = '测试' },
    @{ pattern = '(?i)debug|diagnos|troubleshoot|\berror\b'; label = '问题诊断' },
    @{ pattern = '(?i)security|authentication|authorization|permission'; label = '安全与权限' },
    @{ pattern = '(?i)code review|\breview\b|\baudit\b|\blint\b'; label = '代码与界面审查' },
    @{ pattern = '(?i)image generation|image editing|photo generation|\bflux\b'; label = '图像生成与处理' },
    @{ pattern = '(?i)\bvideo\b'; label = '视频处理' },
    @{ pattern = '(?i)audio|music|speech|voice|tts'; label = '音频与语音' },
    @{ pattern = '(?i)\bpdf\b|\bdocx\b|latex|document'; label = '文档处理' },
    @{ pattern = '(?i)\bpptx?\b|presentation|slides?'; label = '演示文稿' },
    @{ pattern = '(?i)spreadsheet|\bexcel\b|\bcsv\b'; label = '表格与数据' },
    @{ pattern = '(?i)github|gitlab|\bissue\b|pull request'; label = '代码仓库协作' },
    @{ pattern = '(?i)memory|recall|remember|context'; label = '记忆与上下文' },
    @{ pattern = '(?i)browser|chrome|playwright'; label = '浏览器自动化' },
    @{ pattern = '(?i)database|postgres|\bsql\b'; label = '数据库' },
    @{ pattern = '(?i)research|paper|citation|literature|peer review'; label = '学术研究与论文' },
    @{ pattern = '(?i)agent|prompt|skill'; label = 'AI Agent 与技能' }
)

function Get-LocalSkillAction {
    param([string]$Text)

    if ($Text -match '(?i)backward compatibility|legacy|original v\d|exact behavior') { return '兼容' }
    if ($Text -match '(?i)\baudit\b|\breview\b|\binspect\b|\bcheck\b|\blint\b') { return '审查' }
    if ($Text -match '(?i)\bdebug\b|diagnos|troubleshoot|\bfix\b') { return '诊断' }
    if ($Text -match '(?i)\bdeploy\b|\bpublish\b') { return '部署' }
    if ($Text -match '(?i)\bconvert\b|\btranslate\b|\bmigrate\b|\bexport\b') { return '转换' }
    if ($Text -match '(?i)\bgenerate\b|\bgeneration\b|\bsynthesize\b') { return '生成' }
    if ($Text -match '(?i)\bcreate\b|\bbuild\b|\bscaffold\b|\bimplement\b') { return '创建' }
    if ($Text -match '(?i)analy[sz]e|\bresearch\b') { return '分析' }
    if ($Text -match '(?i)\bmanage\b|\bmaintain\b|\borganize\b') { return '管理' }
    if ($Text -match '(?i)optimi[sz]|\bperformance\b') { return '优化' }
    if ($Text -match '(?i)\brender\b') { return '渲染' }
    if ($Text -match '(?i)\bdownload\b|\bfetch\b|\bcapture\b') { return '获取' }
    if ($Text -match '(?i)\bwrite\b|\bauthor\b') { return '编写' }
    if ($Text -match '(?i)\bguide\b|\blearn\b|\bonboard\b') { return '指导' }
    if ($Text -match '(?i)\bdesign\b|\bux/?ui\b|\bvisual\b') { return '设计' }
    return '处理'
}

function Get-AutoChineseSkillDescription {
    param(
        [string]$Skill,
        [string]$Category,
        [object]$Metadata
    )

    $description = ConvertTo-NormalizedSkillText -Text ([string]$Metadata.description)
    $bodyExcerpt = ConvertTo-NormalizedSkillText -Text ([string]$Metadata.body_excerpt)
    $source = if ($description) { $description } else { $bodyExcerpt }
    if ($source -match '^\s*[\p{IsCJKUnifiedIdeographs}]') {
        $candidate = ConvertTo-NormalizedSkillText -Text (($source -split '[。！？!?]')[0])
        if ($candidate.Length -gt 110) { $candidate = $candidate.Substring(0, 110).Trim() }
        if ($candidate) { return $candidate }
    }

    $semanticText = "$Skill $source"
    $labels = [System.Collections.Generic.List[string]]::new()
    foreach ($rule in $skillSemanticRules) {
        if ([regex]::IsMatch($semanticText, [string]$rule.pattern) -and -not $labels.Contains([string]$rule.label)) {
            [void]$labels.Add([string]$rule.label)
        }
    }
    if ($labels.Count -gt 1) {
        [void]$labels.Remove('AI Agent 与技能')
    }
    if ($labels.Contains('GSAP 动效')) {
        [void]$labels.Remove('动效与交互')
    }
    $action = Get-LocalSkillAction -Text $source
    switch ($action) {
        '审查' { [void]$labels.Remove('代码与界面审查') }
        '诊断' { [void]$labels.Remove('问题诊断') }
        '部署' { [void]$labels.Remove('部署与发布') }
        '优化' { [void]$labels.Remove('性能优化') }
    }
    $categoryLabel = if ($categoryLabels.ContainsKey($Category)) { [string]$categoryLabels[$Category] } else { "通用自动化" }
    $subject = if ($labels.Count) { (@($labels | Select-Object -First 4) -join '、') } else { $categoryLabel }
    $displaySubject = if ($subject -match '^[A-Za-z0-9]') { " $subject" } else { $subject }

    switch ($action) {
        '兼容' { return "保留${displaySubject}的旧版行为，适合需要精确兼容和稳定复现的项目。" }
        '审查' { return "用于审查${displaySubject}，检查质量、规范和潜在问题。" }
        '诊断' { return "用于诊断并解决${displaySubject}相关问题，帮助定位原因并给出修复建议。" }
        '部署' { return "用于部署${displaySubject}，覆盖发布前检查、配置和交付流程。" }
        '转换' { return "用于转换${displaySubject}，帮助完成格式、内容或工程迁移。" }
        '生成' { return "用于生成${displaySubject}，提供从输入到成品的结构化流程。" }
        '创建' { return "用于创建${displaySubject}，提供实现步骤、约束和常用实践。" }
        '分析' { return "用于分析${displaySubject}，整理关键信息并给出可执行结论。" }
        '管理' { return "用于管理${displaySubject}，帮助维护配置、内容和工作流程。" }
        '优化' { return "用于优化${displaySubject}，关注性能、质量和可维护性。" }
        '渲染' { return "用于渲染${displaySubject}，处理生成、预览和输出流程。" }
        '获取' { return "用于获取${displaySubject}，处理采集、下载或读取后的后续操作。" }
        '编写' { return "用于编写${displaySubject}，提供结构、规范和质量检查建议。" }
        '指导' { return "用于指导${displaySubject}的使用，帮助选择正确流程并完成配置。" }
        '设计' { return "用于设计${displaySubject}，覆盖视觉规范、排版、布局与交互实现。" }
        default { return "用于处理${displaySubject}相关任务，提供本地 SKILL.md 中定义的流程、约束和实践建议。" }
    }
}

$catalogPath = Join-Path $cfg.output_dir "skill_catalog.json"
function Read-ExistingCatalog {
    param([string]$Path)

    $catalog = @{}
    if (-not (Test-Path $Path)) { return $catalog }
    try {
        $catalogItems = @(Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
        foreach ($item in $catalogItems) {
            foreach ($entry in @($item)) {
                if ($entry.skill) { $catalog[[string]$entry.skill] = $entry }
            }
        }
    } catch {
        Write-Warning "Could not parse existing skill_catalog.json; keeping the last generated catalog for this scan."
    }
    return $catalog
}

# Regex: match skill path, match any known timestamp field (supports ISO and Unix epoch)
$skillRx  = [System.Text.RegularExpressions.Regex]'skills(?:[/\\]|\\\\)+([A-Za-z0-9\-_]+)(?:[/\\]|\\\\)+SKILL\.md'
$skillFileReadRx = [System.Text.RegularExpressions.Regex]'(?i)\b(Get-Content|cat|type)\b[^\r\n]*skills(?:[/\\]|\\\\)+([A-Za-z0-9\-_]+)(?:[/\\]|\\\\)+SKILL\.md'
$claudeAttributionSkillRx = [System.Text.RegularExpressions.Regex]'"attributionSkill"\s*:\s*"([^"]+)"'
$slashSkillRx = [System.Text.RegularExpressions.Regex]'(?m)^\s*/([A-Za-z0-9][A-Za-z0-9:_\-]*)(?=\s|$)'
$commandNameSkillRx = [System.Text.RegularExpressions.Regex]'(?is)<command-name>\s*/([A-Za-z0-9][A-Za-z0-9:_\-]*)\s*</command-name>'
$userRequestRx = [System.Text.RegularExpressions.Regex]'(?is)<USER_REQUEST>\s*(.*?)\s*</USER_REQUEST>'
$directSkillViewPathRx = [System.Text.RegularExpressions.Regex]'(?im)^\s*File Path:\s*`?(?:file:)?[^`\r\n]*[/\\]SKILL\.md`?\s*$'
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

function Get-ExplicitSkillCommands {
    param([string]$Line)

    $texts = [System.Collections.Generic.List[string]]::new()
    try {
        $record = $Line | ConvertFrom-Json -ErrorAction Stop
        if ($record.type -eq 'USER_INPUT') {
            if ($record.content -is [string]) { [void]$texts.Add($record.content) }
            if ($record.text -is [string]) { [void]$texts.Add($record.text) }
        } elseif ($record.type -eq 'response_item' -and
                  $record.payload.type -eq 'message' -and
                  $record.payload.role -eq 'user') {
            foreach ($part in @($record.payload.content)) {
                if ($part.type -eq 'input_text' -and $part.text -is [string]) {
                    [void]$texts.Add($part.text)
                }
            }
        } elseif ($record.type -eq 'event_msg' -and
                  $record.payload.type -eq 'user_message' -and
                  $record.payload.message -is [string]) {
            [void]$texts.Add($record.payload.message)
        }
    } catch {
        # Some tools emit plain text. Only accept their explicit command/request tags.
        if ($Line.Contains('<command-name>') -or $Line.Contains('<USER_REQUEST>')) {
            [void]$texts.Add($Line)
        }
    }

    $commands = [System.Collections.Generic.List[string]]::new()
    foreach ($text in $texts) {
        # Codex slash commands arrive inside this tag. Keep only installed skills so
        # built-in commands such as /model do not become catalog entries.
        foreach ($m in $commandNameSkillRx.Matches($text)) {
            $command = $m.Groups[1].Value
            if ($counts.ContainsKey($command)) {
                [void]$commands.Add($command)
            }
        }

        $requestMatches = $userRequestRx.Matches($text)
        if ($requestMatches.Count -gt 0) {
            foreach ($request in $requestMatches) {
                foreach ($m in $slashSkillRx.Matches($request.Groups[1].Value)) {
                    $command = $m.Groups[1].Value
                    if ($counts.ContainsKey($command)) {
                        [void]$commands.Add($command)
                    }
                }
            }
        } else {
            foreach ($m in $slashSkillRx.Matches($text)) {
                $command = $m.Groups[1].Value
                if ($counts.ContainsKey($command)) {
                    [void]$commands.Add($command)
                }
            }
        }
    }

    return @($commands | Select-Object -Unique)
}

function Test-SkillReadLine {
    param([string]$Line)
    if (-not $Line.Contains('SKILL.md')) { return $false }
    if ($Line.Contains('"type":"function_call_output"')) { return $false }
    if ($Line.Contains('[external_agent_tool_result]')) { return $false }
    if ($Line.Contains('"type":"GREP_SEARCH"')) { return $false }
    if ($Line.Contains('"type":"RUN_COMMAND"')) { return $false }
    if ($Line.Contains('Skills 清单') -or $Line.Contains('已下载的 Skills')) { return $false }

    if ($Line.Contains('"type":"VIEW_FILE"')) {
        try {
            $record = $Line | ConvertFrom-Json -ErrorAction Stop
            return $directSkillViewPathRx.IsMatch([string]$record.content)
        } catch {
            return $directSkillViewPathRx.IsMatch($Line)
        }
    }

    return (
        $Line.Contains('[external_agent_tool_call: Read]') -or
        $Line.Contains('"name":"Read"') -or
        $Line.Contains('"name":"view_file"') -or
        ($Line -match '(?i)\b(Get-Content|cat)\b[^\r\n]*SKILL\.md')
    )
}

# ── Watch Loop Setup ───────────────────────────────────────────────────────────
$fileStates = @{}

$pidPath = Join-Path $cfg.output_dir ".collector.pid"
$watcherMutex = $null
$ownsWatcherMutex = $false
if ($Watch) {
    $mutexHash = Get-StableId ([System.IO.Path]::GetFullPath($cfg.output_dir).ToLowerInvariant())
    $watcherMutex = [System.Threading.Mutex]::new($false, "Local\SkillTrackerCollector_$mutexHash")
    try {
        if (-not $watcherMutex.WaitOne(0, $false)) {
            Write-Host "A Skill Tracker watcher is already running for $($cfg.output_dir)."
            exit 0
        }
    } catch [System.Threading.AbandonedMutexException] {
        # An earlier watcher ended unexpectedly; this process now owns the lock.
    }
    $ownsWatcherMutex = $true
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

function Get-SkillFilesState {
    $state = @{}
    foreach ($root in $skillRoots) {
        $skillFiles = Get-ChildItem -Path $root -Recurse -Filter "SKILL.md" -File -ErrorAction SilentlyContinue |
                      Where-Object { $_.FullName.Substring($root.Length) -notmatch '[\\/]\.[^\\/]' }
        foreach ($skillFile in $skillFiles) {
            $state[$skillFile.FullName] = @{
                LastWriteTimeUtc = $skillFile.LastWriteTimeUtc
                Length           = $skillFile.Length
            }
        }
    }
    return $state
}

$global:fileCache = @{}
$firstRun = $true
$skillFileStates = Get-SkillFilesState

try {
    while ($true) {
    if ($Watch) {
        $currentState = Get-LogFilesState
        $currentSkillState = Get-SkillFilesState
        $changed = $false
        $skillsChanged = $false

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

        foreach ($key in $currentSkillState.Keys) {
            if (-not $skillFileStates.ContainsKey($key)) {
                $skillsChanged = $true
                break
            }
            $old = $skillFileStates[$key]
            $new = $currentSkillState[$key]
            if ($old.LastWriteTimeUtc -ne $new.LastWriteTimeUtc -or $old.Length -ne $new.Length) {
                $skillsChanged = $true
                break
            }
        }
        if (-not $skillsChanged) {
            foreach ($key in $skillFileStates.Keys) {
                if (-not $currentSkillState.ContainsKey($key)) {
                    $skillsChanged = $true
                    break
                }
            }
        }
        if ($skillsChanged) { $changed = $true }

        if (-not $changed) {
            Start-Sleep -Seconds 5
            continue
        }

        $fileStates = $currentState
        $skillFileStates = $currentSkillState
        if ($skillsChanged) {
            Update-SkillInventory
            Write-Host "Local SKILL.md files updated. Re-scanning..."
        }
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

                    # Claude Code exposes an explicit attribution field. Other tools are
                    # counted only from explicit slash invocations or real skill-file reads.
                    if ($line.Contains('"attributionSkill"')) {
                        foreach ($m in $claudeAttributionSkillRx.Matches($line)) {
                            [void]$lineSkills.Add($m.Groups[1].Value)
                        }
                    }

                    foreach ($cmd in Get-ExplicitSkillCommands -Line $line) {
                        [void]$lineSkills.Add($cmd)
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
$existingCatalog = Read-ExistingCatalog -Path $catalogPath
$catalogArr = @()
$arr = @()
foreach ($kv in $counts.GetEnumerator() | Sort-Object Name) {
    $skill = $kv.Key
    $existing = $existingCatalog[$skill]
    $category = Get-SkillCategory $skill
    $metadata = if ($skillMetadata.ContainsKey($skill)) { $skillMetadata[$skill] } else {
        [PSCustomObject]@{ description = $descs[$skill]; zh_description = ""; triggers = @(); body_excerpt = "" }
    }
    $translationInput = ConvertTo-NormalizedSkillText -Text ("$skill`n$($metadata.description)`n$($metadata.zh_description)`n$($metadata.body_excerpt)")
    $translationInputHash = Get-StableId -Value $translationInput
    $zhDesc = ""
    $zhDescSource = ""
    $translationVersionOut = ""

    # Existing catalog entries without a source marker predate automatic parsing.
    # Treat those as manual so imports and user-maintained text can never be overwritten.
    $existingDesc = if ($existing) { ConvertTo-NormalizedSkillText -Text ([string]$existing.zh_desc) } else { "" }
    $existingSource = if ($existing) { [string]$existing.zh_desc_source } else { "" }
    $existingInputHash = if ($existing) { [string]$existing.zh_desc_input_hash } else { "" }
    if ($existingDesc -and (-not $existingSource -or $existingSource -eq "manual")) {
        $zhDesc = $existingDesc
        $zhDescSource = "manual"
    } elseif ($existingDesc -and $existingSource -match '^auto' -and $existingInputHash -eq $translationInputHash -and [string]$existing.translation_version -eq $translationVersion) {
        $zhDesc = $existingDesc
        $zhDescSource = $existingSource
        $translationVersionOut = if ($existing.translation_version) { [string]$existing.translation_version } else { $translationVersion }
    }
    if (-not $zhDesc -and $metadata.zh_description) {
        $zhDesc = ConvertTo-NormalizedSkillText -Text ([string]$metadata.zh_description)
        $zhDescSource = "frontmatter"
        $translationVersionOut = "frontmatter"
    }
    if (-not $zhDesc) {
        $zhDesc = Get-AutoChineseSkillDescription -Skill $skill -Category $category -Metadata $metadata
        $zhDescSource = "auto_rule"
        $translationVersionOut = $translationVersion
    }

    $sourcePath = if ($skillSourcePaths.ContainsKey($skill)) { $skillSourcePaths[$skill] } else { "" }
    $triggers = if ($metadata.triggers -and @($metadata.triggers).Count -gt 0) {
        @($metadata.triggers)
    } elseif ($existing -and $existing.triggers) {
        @($existing.triggers)
    } else {
        @()
    }

    $catalogItem = [PSCustomObject]@{
        skill               = $skill
        category            = $category
        zh_desc             = $zhDesc
        zh_desc_source      = $zhDescSource
        zh_desc_input_hash  = if ($zhDescSource -match '^auto|frontmatter') { $translationInputHash } else { "" }
        translation_version = $translationVersionOut
        english_desc        = $descs[$skill]
        triggers            = $triggers
        source_path         = $sourcePath
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

[System.IO.File]::WriteAllText($catalogPath, (ConvertTo-Json -InputObject @($catalogArr) -Depth 8 -Compress), [System.Text.Encoding]::UTF8)
$catalogJsPath = Join-Path $cfg.output_dir "skill_catalog.js"
$catalogJson = ConvertTo-Json -InputObject @($catalogArr) -Depth 8 -Compress
[System.IO.File]::WriteAllText($catalogJsPath, "var SKILL_CATALOG = $catalogJson;`n", [System.Text.Encoding]::UTF8)

# ── Output skill_data.js ───────────────────────────────────────────────────────
$sb = [System.Text.StringBuilder]::new()
$skillDataJson = ConvertTo-Json -InputObject @($arr) -Depth 6 -Compress
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
$logJson = ConvertTo-Json -InputObject @($sorted) -Depth 6 -Compress
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
    if ($watcherMutex) {
        if ($ownsWatcherMutex) {
            try { $watcherMutex.ReleaseMutex() } catch { }
        }
        $watcherMutex.Dispose()
    }
}
