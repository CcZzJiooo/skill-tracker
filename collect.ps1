<#
.SYNOPSIS
  Skill Tracker — collect AI skill call logs across all AI coding tools.
#>
param(
    [string]$SkillsRoot = "",
    [string]$ConfigFile = "$PSScriptRoot/config.json",
    [string]$OutputDir  = "",
    [switch]$Watch,
    [switch]$ForceScan,
    [int]$RecentFiles = 0,
    [int]$RecentDays = 0
)

# ── Load config ────────────────────────────────────────────────────────────────
$cfg = @{ skills_root=""; skills_roots=@(); output_dir="./dashboard"; max_log_entries=5000; dedup_window_minutes=2; custom_tools=@() }
$resolvedConfigFile = if ([System.IO.Path]::IsPathRooted($ConfigFile)) {
    [System.IO.Path]::GetFullPath($ConfigFile)
} else {
    [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $ConfigFile))
}
if (-not (Test-Path -LiteralPath $resolvedConfigFile -PathType Leaf) -and -not [System.IO.Path]::IsPathRooted($ConfigFile)) {
    $packageConfig = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $ConfigFile))
    if (Test-Path -LiteralPath $packageConfig -PathType Leaf) { $resolvedConfigFile = $packageConfig }
}
$configBaseDir = Split-Path -Parent $resolvedConfigFile
function Resolve-ConfiguredPath {
    param(
        [string]$Path,
        [string]$BaseDirectory = $configBaseDir
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    $expanded = [Environment]::ExpandEnvironmentVariables([string]$Path).Trim()
    $configuredHome = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { "" }
    if ($configuredHome -and $expanded -match '^~([\\/]|$)') {
        $expanded = $configuredHome + $expanded.Substring(1)
    }
    if ([System.IO.Path]::IsPathRooted($expanded)) {
        return [System.IO.Path]::GetFullPath($expanded)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $BaseDirectory $expanded))
}
if (Test-Path -LiteralPath $resolvedConfigFile -PathType Leaf) {
    try {
        $raw = Get-Content -LiteralPath $resolvedConfigFile -Raw | ConvertFrom-Json
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
$outputBaseDir = if ($OutputDir) { $PSScriptRoot } else { $configBaseDir }
$cfg.output_dir = Resolve-ConfiguredPath -Path ([string]$cfg.output_dir) -BaseDirectory $outputBaseDir
New-Item -ItemType Directory -Path $cfg.output_dir -Force | Out-Null

# ── Auto-detect skills roots ───────────────────────────────────────────────────
$userHome = $env:USERPROFILE
if (-not $userHome) { $userHome = $env:HOME }
$codexHome = if ($env:CODEX_HOME) {
    Resolve-ConfiguredPath -Path ([string]$env:CODEX_HOME) -BaseDirectory (Get-Location).Path
} else {
    [System.IO.Path]::Combine($userHome, ".codex")
}
$dshSessionRoot = if ($env:DSH_SESSION_ROOT) {
    Resolve-ConfiguredPath -Path ([string]$env:DSH_SESSION_ROOT) -BaseDirectory (Get-Location).Path
} else {
    [System.IO.Path]::Combine($userHome, ".dsh", "sessions")
}
$runningOnWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
$runningOnMacOS = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)
$runtimePlatform = if ($runningOnWindows) { "Windows" } elseif ($runningOnMacOS) { "MacOS" } else { "Linux" }
$platformModule = Join-Path $PSScriptRoot "tools/platform-paths.psm1"
if (-not (Test-Path -LiteralPath $platformModule -PathType Leaf)) {
    throw "Platform path module not found: $platformModule"
}
Import-Module $platformModule -Force
$platformArgs = @{
    Platform = $runtimePlatform
    UserHome = $userHome
}
if ($runningOnWindows) {
    $platformArgs.AppData = $env:APPDATA
    $platformArgs.LocalAppData = $env:LOCALAPPDATA
    $platformArgs.ProgramFiles = $env:ProgramFiles
    $platformArgs.ProgramFilesX86 = ${env:ProgramFiles(x86)}
}
$platformPaths = Get-SkillTrackerPlatformPaths @platformArgs
$appData = $platformPaths.AppData
$localAppData = $platformPaths.LocalAppData
$editorGlobalStorageRoots = @($platformPaths.EditorGlobalStorageRoots)
$editorWorkspaceStorageRoots = @($platformPaths.EditorWorkspaceStorageRoots)

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

# Extension globalStorage can survive an uninstall, so it is a log source but
# not a reliable installation marker. The package directories below are the
# bounded, user-owned locations where VS Code-compatible extensions are
# actually installed. This keeps a removed extension from being resurrected by
# stale globalStorage data.
$editorExtensionInstallRoots = @(
    (Join-SkillTrackerPath $userHome ".vscode" "extensions"),
    (Join-SkillTrackerPath $userHome ".vscode-insiders" "extensions"),
    (Join-SkillTrackerPath $userHome ".cursor" "extensions"),
    (Join-SkillTrackerPath $userHome ".windsurf" "extensions"),
    (Join-SkillTrackerPath $userHome ".trae" "extensions"),
    (Join-SkillTrackerPath $userHome ".trae-cn" "extensions"),
    (Join-SkillTrackerPath $userHome ".kiro" "extensions"),
    (Join-SkillTrackerPath $appData "Code" "User" "extensions"),
    (Join-SkillTrackerPath $appData "Code - Insiders" "User" "extensions"),
    (Join-SkillTrackerPath $appData "VSCodium" "User" "extensions"),
    (Join-SkillTrackerPath $appData "Cursor" "User" "extensions"),
    (Join-SkillTrackerPath $appData "Windsurf" "User" "extensions"),
    (Join-SkillTrackerPath $appData "Trae" "User" "extensions"),
    (Join-SkillTrackerPath $appData "Trae CN" "User" "extensions"),
    (Join-SkillTrackerPath $appData "Qoder" "User" "extensions"),
    (Join-SkillTrackerPath $appData "Qoder CN" "User" "extensions"),
    (Join-SkillTrackerPath $appData "CodeBuddy" "User" "extensions")
) | Where-Object { $_ } | Select-Object -Unique

function Get-EditorExtensionInstallPatterns {
    param([string[]]$ExtensionIds)

    $patterns = @()
    foreach ($root in @($editorExtensionInstallRoots)) {
        if (-not $root) { continue }
        foreach ($id in @($ExtensionIds)) {
            if ($id) { $patterns += (Join-SkillTrackerPath $root ([string]$id + "-*")) }
        }
    }
    return @($patterns | Select-Object -Unique)
}

$skillRootCandidates = @(
    (Join-SkillTrackerPath $PSScriptRoot ".agents" "skills"),
    (Join-SkillTrackerPath $PSScriptRoot ".cursor" "skills"),
    (Join-SkillTrackerPath $PSScriptRoot ".codex" "skills"),
    (Join-SkillTrackerPath $PSScriptRoot ".codex" "plugins" "cache"),
    (Join-SkillTrackerPath $codexHome "skills"),
    (Join-SkillTrackerPath $codexHome "plugins" "cache"),
    (Join-SkillTrackerPath $userHome ".agents" "skills"),
    (Join-SkillTrackerPath $userHome ".config" "agents" "skills"),
    (Join-SkillTrackerPath $userHome ".claude" "skills"),
    (Join-SkillTrackerPath $userHome ".hermes" "skills"),
    (Join-SkillTrackerPath $userHome ".cursor" "skills"),
    (Join-SkillTrackerPath $userHome ".cline" "skills"),
    (Join-SkillTrackerPath $userHome ".roo" "skills"),
    (Join-SkillTrackerPath $userHome ".kilo" "skills"),
    (Join-SkillTrackerPath $userHome ".qwen" "skills"),
    (Join-SkillTrackerPath $userHome ".dsh" "skills"),
    (Join-SkillTrackerPath $userHome ".workbuddy" "skills"),
    (Join-SkillTrackerPath $userHome ".codebuddy" "skills"),
    (Join-SkillTrackerPath $userHome ".qoder" "skills"),
    (Join-SkillTrackerPath $userHome ".lingma" "skills"),
    (Join-SkillTrackerPath $userHome ".config" "amp" "skills"),
    (Join-SkillTrackerPath $userHome ".config" "opencode" "skills"),
    (Join-SkillTrackerPath $userHome ".opencode" "skills"),
    (Join-SkillTrackerPath $userHome ".gemini" "config" "skills"),
    (Join-SkillTrackerPath $userHome ".config" "gemini" "skills"),
    (Join-SkillTrackerPath $userHome ".cc-switch" "skills")
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
if ($cfg.skills_root) {
    $cfg.skills_root = Resolve-ConfiguredPath -Path ([string]$cfg.skills_root)
    Add-SkillRoot -Path $cfg.skills_root
}
if ($cfg.skills_roots) {
    $cfg.skills_roots = @($cfg.skills_roots | ForEach-Object {
        Resolve-ConfiguredPath -Path ([string]$_)
    })
}
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
$commonProgramRoots = @($platformPaths.CommonProgramRoots)
function Get-DesktopInstallPaths {
    param(
        [string]$DirectoryName,
        [string]$ExecutableName
    )

    if ($runtimePlatform -eq "MacOS") {
        return @($commonProgramRoots | Where-Object { $_ -match '(?i)Applications$' } | ForEach-Object {
            Join-SkillTrackerPath $_ "$DirectoryName.app"
        })
    }
    if ($runtimePlatform -eq "Linux") { return @() }
    return @($commonProgramRoots | ForEach-Object { Join-SkillTrackerPath $_ $DirectoryName $ExecutableName })
}

$desktopToolPolicies = @{
    # Antigravity and AntigravityIDE are separate products and must not share
    # an install marker or a source row. Keep each product's legacy/current
    # executable layout inside its own policy.
    "Antigravity"   = @{ InstallPaths = @(Get-DesktopInstallPaths -DirectoryName "Antigravity" -ExecutableName "Antigravity.exe"); CommandNames = @("antigravity"); ProcessNames = @("Antigravity") }
    "AntigravityIDE" = @{ InstallPaths = @(Get-DesktopInstallPaths -DirectoryName "Antigravity IDE" -ExecutableName "Antigravity IDE.exe"); CommandNames = @("antigravity-ide"); ProcessNames = @("Antigravity IDE") }
    "Cursor"      = @{ InstallPaths = @(Get-DesktopInstallPaths -DirectoryName "Cursor" -ExecutableName "Cursor.exe"); CommandNames = @("cursor"); ProcessNames = @("Cursor") }
    "Windsurf"    = @{ InstallPaths = @(Get-DesktopInstallPaths -DirectoryName "Windsurf" -ExecutableName "Windsurf.exe"); CommandNames = @("windsurf"); ProcessNames = @("Windsurf") }
    "Trae"        = @{ InstallPaths = @(Get-DesktopInstallPaths -DirectoryName "Trae" -ExecutableName "Trae.exe"); CommandNames = @("trae"); ProcessNames = @("Trae") }
    "Zed"         = @{ InstallPaths = @(Get-DesktopInstallPaths -DirectoryName "Zed" -ExecutableName "Zed.exe"); CommandNames = @("zed"); ProcessNames = @("Zed") }
}

function Get-CommandInstallPaths {
    param([string[]]$CommandNames)

    $roots = @(
        (Join-SkillTrackerPath $appData "npm"),
        (Join-SkillTrackerPath $localAppData "npm"),
        (Join-SkillTrackerPath $userHome ".npm-global" "bin"),
        (Join-SkillTrackerPath $userHome ".local" "bin")
    ) | Where-Object { $_ } | Select-Object -Unique
    $suffixes = if ($runtimePlatform -eq "Windows") { @(".cmd", ".ps1", ".exe", "") } else { @("", ".sh") }
    $paths = @()
    foreach ($root in $roots) {
        foreach ($name in @($CommandNames)) {
            foreach ($suffix in $suffixes) {
                $paths += (Join-SkillTrackerPath $root ([string]$name + $suffix))
            }
        }
    }
    return @($paths | Select-Object -Unique)
}

function Get-NpmPackageInstallPatterns {
    param([string[]]$PackageNames)

    $globalRoots = @(
        (Join-SkillTrackerPath $appData "npm" "node_modules"),
        (Join-SkillTrackerPath $localAppData "npm" "node_modules"),
        (Join-SkillTrackerPath $userHome ".npm-global" "lib" "node_modules"),
        (Join-SkillTrackerPath $userHome ".npm" "node_modules")
    ) | Where-Object { $_ } | Select-Object -Unique
    $npxRoots = @(
        (Join-SkillTrackerPath $appData "npm-cache" "_npx"),
        (Join-SkillTrackerPath $localAppData "npm-cache" "_npx"),
        (Join-SkillTrackerPath $userHome ".npm" "_npx")
    ) | Where-Object { $_ } | Select-Object -Unique
    $patterns = @()
    foreach ($packageName in @($PackageNames)) {
        if (-not $packageName) { continue }
        $packageParts = ([string]$packageName).Split('/', 2)
        foreach ($root in $globalRoots) {
            $patterns += if ($packageParts.Count -eq 2) {
                Join-SkillTrackerPath $root $packageParts[0] $packageParts[1] "package.json"
            } else {
                Join-SkillTrackerPath $root $packageParts[0] "package.json"
            }
        }
        foreach ($root in $npxRoots) {
            $patterns += if ($packageParts.Count -eq 2) {
                Join-SkillTrackerPath $root "*" "node_modules" $packageParts[0] $packageParts[1] "package.json"
            } else {
                Join-SkillTrackerPath $root "*" "node_modules" $packageParts[0] "package.json"
            }
        }
    }
    return @($patterns | Select-Object -Unique)
}

$transcriptTools = @("Antigravity", "AntigravityIDE")
$AUTO_DETECT_TOOLS = @(
    @{ Name="Antigravity";   Paths=@((Join-SkillTrackerPath $userHome ".gemini" "antigravity" "brain")); TsField="created_at"; RequireInstall=$true; InstallPaths=$desktopToolPolicies["Antigravity"].InstallPaths; CommandNames=$desktopToolPolicies["Antigravity"].CommandNames; ProcessNames=$desktopToolPolicies["Antigravity"].ProcessNames },
    @{ Name="AntigravityIDE"; Paths=@((Join-SkillTrackerPath $userHome ".gemini" "antigravity-ide" "brain")); TsField="created_at"; RequireInstall=$true; InstallPaths=$desktopToolPolicies["AntigravityIDE"].InstallPaths; CommandNames=$desktopToolPolicies["AntigravityIDE"].CommandNames; ProcessNames=$desktopToolPolicies["AntigravityIDE"].ProcessNames },
    @{ Name="Aider";       Paths=@((Join-SkillTrackerPath $PSScriptRoot ".aider.chat.history.md"),(Join-SkillTrackerPath $PSScriptRoot ".aider.llm.history"),(Join-SkillTrackerPath $userHome ".aider.chat.history.md"),(Join-SkillTrackerPath $userHome ".aider.llm.history")); TsField="timestamp" },
    @{ Name="Amazon Q";    Paths=@(Get-EditorGlobalStoragePaths -ExtensionIds @("amazonwebservices.amazon-q-vscode","amazonwebservices.aws-toolkit-vscode")); TsField="timestamp" },
    @{ Name="Amp";         Paths=@((Join-SkillTrackerPath $userHome ".config" "amp"),(Join-SkillTrackerPath $appData "amp"),(Join-SkillTrackerPath $localAppData "amp")); TsField="timestamp" },
    @{ Name="Augment";     Paths=@(Get-EditorGlobalStoragePaths -ExtensionIds @("augment.vscode-augment","augment.vscode-augment-nightly")); TsField="timestamp" },
    @{ Name="ClaudeCode";  Paths=@((Join-SkillTrackerPath $userHome ".claude" "projects")); TsField="timestamp" },
    @{ Name="Cline";       Paths=@(Get-EditorGlobalStoragePaths -ExtensionIds @("saoudrizwan.claude-dev","cline.cline")); TsField="timestamp" },
    @{ Name="Codex";       Paths=@((Join-SkillTrackerPath $codexHome "archived_sessions"),(Join-SkillTrackerPath $codexHome "sessions")); TsField="timestamp" },
    @{ Name="Cursor";      Paths=@((Join-SkillTrackerPath $userHome ".cursor" "logs"),(Join-SkillTrackerPath $appData "Cursor" "logs")); TsField="timestamp"; RequireInstall=$true; InstallPaths=$desktopToolPolicies["Cursor"].InstallPaths; CommandNames=$desktopToolPolicies["Cursor"].CommandNames; ProcessNames=$desktopToolPolicies["Cursor"].ProcessNames },
    @{ Name="Windsurf";    Paths=@((Join-SkillTrackerPath $userHome ".codeium" "windsurf" "logs"),(Join-SkillTrackerPath $appData "Windsurf" "logs")); TsField="timestamp"; RequireInstall=$true; InstallPaths=$desktopToolPolicies["Windsurf"].InstallPaths; CommandNames=$desktopToolPolicies["Windsurf"].CommandNames; ProcessNames=$desktopToolPolicies["Windsurf"].ProcessNames },
    @{ Name="WorkBuddy";   Paths=@((Join-SkillTrackerPath $userHome ".workbuddy" "projects"),(Join-SkillTrackerPath $userHome ".workbuddy" "sessions"),(Join-SkillTrackerPath $userHome ".workbuddy" "logs"),(Join-SkillTrackerPath $appData "WorkBuddy" "logs"),(Join-SkillTrackerPath $localAppData "WorkBuddy" "logs"),(Join-SkillTrackerPath $appData "Tencent" "WorkBuddy" "Logs"),(Join-SkillTrackerPath $localAppData "Tencent" "WorkBuddy" "Logs")); TsField="timestamp"; Id="workbuddy"; Aliases=@("workbuddy"); Publisher="Tencent"; RuntimeKind="agent_harness"; ProviderHints=@("Tencent") },
    @{ Name="CodeBuddy";   Paths=@((Join-SkillTrackerPath $userHome ".codebuddy" "logs"),(Join-SkillTrackerPath $userHome ".codebuddy" "projects"),(Join-SkillTrackerPath $appData "CodeBuddy" "logs"),(Join-SkillTrackerPath $localAppData "CodeBuddy" "logs"),(Join-SkillTrackerPath $appData "Tencent" "CodeBuddy" "logs"),(Join-SkillTrackerPath $localAppData "Tencent" "CodeBuddy" "logs")); TsField="timestamp"; Id="codebuddy"; Aliases=@("codebuddy"); Publisher="Tencent"; RuntimeKind="coding_agent"; ProviderHints=@("Tencent") },
    @{ Name="Qoder";      Paths=@((Join-SkillTrackerPath $userHome ".qoder" "projects"),(Join-SkillTrackerPath $userHome ".qoder" "sessions"),(Join-SkillTrackerPath $userHome ".qoder" "logs"),(Join-SkillTrackerPath $userHome ".lingma" "projects"),(Join-SkillTrackerPath $userHome ".lingma" "sessions"),(Join-SkillTrackerPath $userHome ".lingma" "logs"),(Join-SkillTrackerPath $appData "Qoder" "logs"),(Join-SkillTrackerPath $localAppData "Qoder" "logs"),(Join-SkillTrackerPath $appData "Lingma" "logs"),(Join-SkillTrackerPath $localAppData "Lingma" "logs")); TsField="timestamp"; Id="qoder"; Aliases=@("qoder-cn","lingma","Tongyi Lingma","通义灵码"); Publisher="Alibaba Cloud"; RuntimeKind="coding_agent"; ProviderHints=@("Alibaba Cloud") },
    @{ Name="CodeGeeX";   Paths=@((Get-EditorGlobalStoragePaths -ExtensionIds @("AMiner.codegeex","aminer.codegeex","codegeex-research.codegeex-research")) + @((Join-SkillTrackerPath $appData "CodeGeeX" "logs"),(Join-SkillTrackerPath $localAppData "CodeGeeX" "logs"))); TsField="timestamp"; Id="codegeex"; Aliases=@("codegeex"); Publisher="AMiner"; RuntimeKind="ide_extension"; ProviderHints=@("AMiner") },
    @{ Name="Baidu Comate"; Paths=@((Get-EditorGlobalStoragePaths -ExtensionIds @("BaiduComate.BaiduComate","baiducomate.baiducomate")) + @((Join-SkillTrackerPath $appData "Comate" "logs"),(Join-SkillTrackerPath $localAppData "Comate" "logs"),(Join-SkillTrackerPath $appData "BaiduComate" "logs"),(Join-SkillTrackerPath $localAppData "BaiduComate" "logs"),(Join-SkillTrackerPath $appData "Baidu" "Comate" "logs"),(Join-SkillTrackerPath $localAppData "Baidu" "Comate" "logs"))); TsField="timestamp"; Id="baidu-comate"; Aliases=@("comate","baiducomate","文心快码"); Publisher="Baidu"; RuntimeKind="ide_extension"; ProviderHints=@("Baidu") },
    @{ Name="Continue";    Paths=@((Join-SkillTrackerPath $userHome ".continue" "sessions")); TsField="timestamp" },
    @{ Name="Gemini CLI";  Paths=@((Join-SkillTrackerPath $userHome ".gemini" "sessions")); TsField="created_at" },
    @{ Name="GitHub Copilot"; Paths=@(Get-EditorGlobalStoragePaths -ExtensionIds @("github.copilot-chat","github.copilot")); TsField="timestamp" },
    @{ Name="Goose";       Paths=@((Join-SkillTrackerPath $userHome ".config" "goose" "sessions"),(Join-SkillTrackerPath $userHome ".local" "share" "goose" "sessions"),(Join-SkillTrackerPath $userHome ".local" "state" "goose" "logs"),(Join-SkillTrackerPath $appData "goose" "sessions"),(Join-SkillTrackerPath $appData "goose" "logs")); TsField="timestamp" },
    @{ Name="Hermes";      Paths=@((Join-SkillTrackerPath $userHome ".hermes" "sessions"),(Join-SkillTrackerPath $userHome ".hermes" "logs"),(Join-SkillTrackerPath $appData "Hermes" "logs"),(Join-SkillTrackerPath $localAppData "Hermes" "logs")); TsField="timestamp"; Aliases=@("hermes-agent") },
    @{ Name="DeepSeek Harness"; Paths=@($dshSessionRoot,(Join-SkillTrackerPath $userHome ".dsh" "logs"),(Join-SkillTrackerPath $appData "dsh" "sessions"),(Join-SkillTrackerPath $appData "dsh" "logs"),(Join-SkillTrackerPath $localAppData "dsh" "sessions"),(Join-SkillTrackerPath $localAppData "dsh" "logs")); TsField="time"; Id="deepseek-harness"; Aliases=@("DeepSeekHarness","deepseekharness","deepseek-harness","dsh"); Publisher="DeepSeek AI"; RuntimeKind="agent_harness"; ProviderHints=@("DeepSeek") },
    @{ Name="JetBrains AI"; Paths=@(Get-EditorGlobalStoragePaths -ExtensionIds @("JetBrains.jetbrains-ai-assistant","jetbrains.jetbrains-ai-assistant")); TsField="timestamp" },
    @{ Name="Junie";       Paths=@((Join-SkillTrackerPath $userHome ".junie" "logs"),(Join-SkillTrackerPath $userHome ".junie" "sessions")); TsField="timestamp" },
    @{ Name="Kilo Code";   Paths=@((Get-EditorGlobalStoragePaths -ExtensionIds @("kilocode.kilo-code","kilo-code.kilo-code")) + @((Join-SkillTrackerPath $userHome ".kilo"),(Join-SkillTrackerPath $appData "kilo"))); TsField="timestamp" },
    @{ Name="OpenCode";    Paths=@((Join-SkillTrackerPath $userHome ".local" "share" "opencode" "log"),(Join-SkillTrackerPath $userHome ".local" "share" "opencode"),(Join-SkillTrackerPath $appData "opencode" "log"),(Join-SkillTrackerPath $appData "opencode"),(Join-SkillTrackerPath $userHome ".config" "opencode")); TsField="timestamp"; Id="opencode"; Aliases=@("opencode") ; Publisher="OpenCode"; RuntimeKind="coding_agent" },
    @{ Name="Qwen Code";   Paths=@((Join-SkillTrackerPath $userHome ".qwen" "logs" "openai"),(Join-SkillTrackerPath $userHome ".qwen" "debug"),(Join-SkillTrackerPath $userHome ".qwen"),(Join-SkillTrackerPath $userHome ".config" "qwen")); TsField="timestamp" },
    @{ Name="Roo Code";    Paths=@(Get-EditorGlobalStoragePaths -ExtensionIds @("rooveterinaryinc.roo-cline","roocode.roo-cline","roo-cline.roo-cline")); TsField="timestamp" },
    @{ Name="Sourcegraph Cody"; Paths=@(Get-EditorGlobalStoragePaths -ExtensionIds @("sourcegraph.cody-ai","sourcegraph.cody")); TsField="timestamp" },
    @{ Name="Tabby";       Paths=@(Get-EditorGlobalStoragePaths -ExtensionIds @("TabbyML.vscode-tabby","tabbyml.vscode-tabby")); TsField="timestamp" },
    @{ Name="Tabnine";     Paths=@((Get-EditorGlobalStoragePaths -ExtensionIds @("TabNine.tabnine-vscode","tabnine.tabnine-vscode")) + @((Join-SkillTrackerPath $userHome ".tabnine"),(Join-SkillTrackerPath $appData "TabNine"),(Join-SkillTrackerPath $appData "Tabnine"))); TsField="timestamp" },
    @{ Name="Trae";        Paths=@((Join-SkillTrackerPath $appData "Trae" "logs"),(Join-SkillTrackerPath $appData "Trae" "User" "workspaceStorage"),(Join-SkillTrackerPath $appData "Trae CN" "logs"),(Join-SkillTrackerPath $localAppData "Trae" "logs")); TsField="timestamp"; RequireInstall=$true; InstallPaths=$desktopToolPolicies["Trae"].InstallPaths; CommandNames=$desktopToolPolicies["Trae"].CommandNames; ProcessNames=$desktopToolPolicies["Trae"].ProcessNames },
    @{ Name="Zed";         Paths=@((Join-SkillTrackerPath $localAppData "Zed" "logs"),(Join-SkillTrackerPath $localAppData "Zed" "conversations"),(Join-SkillTrackerPath $appData "Zed" "logs"),(Join-SkillTrackerPath $userHome ".config" "zed" "conversations"),(Join-SkillTrackerPath $userHome ".local" "share" "zed" "conversations"),(Join-SkillTrackerPath $userHome ".local" "share" "zed" "logs")); TsField="timestamp"; RequireInstall=$true; InstallPaths=$desktopToolPolicies["Zed"].InstallPaths; CommandNames=$desktopToolPolicies["Zed"].CommandNames; ProcessNames=$desktopToolPolicies["Zed"].ProcessNames }
)

# Every built-in profile now needs fresh installation evidence. Historical log
# directories remain diagnostic sources, but by themselves they no longer make
# a deleted tool look installed. CLI profiles use command/package markers;
# editor extensions use their versioned installation directories.
$toolInstallPolicies = @{
    "Aider" = @{ CommandNames=@("aider"); InstallPaths=@(Get-CommandInstallPaths -CommandNames @("aider")) }
    "Amazon Q" = @{ InstallPathPatterns=@(Get-EditorExtensionInstallPatterns -ExtensionIds @("amazonwebservices.amazon-q-vscode","amazonwebservices.aws-toolkit-vscode")) }
    "Amp" = @{ CommandNames=@("amp"); InstallPaths=@(Get-CommandInstallPaths -CommandNames @("amp")) }
    "Augment" = @{ InstallPathPatterns=@(Get-EditorExtensionInstallPatterns -ExtensionIds @("augment.vscode-augment","augment.vscode-augment-nightly")) }
    "ClaudeCode" = @{ CommandNames=@("claude"); InstallPaths=@(Get-CommandInstallPaths -CommandNames @("claude")) }
    "Cline" = @{ InstallPathPatterns=@(Get-EditorExtensionInstallPatterns -ExtensionIds @("saoudrizwan.claude-dev","cline.cline")) }
    "Codex" = @{ CommandNames=@("codex"); ProcessNames=@("codex"); InstallPaths=@((Join-SkillTrackerPath $localAppData "OpenAI" "Codex")) + @(Get-CommandInstallPaths -CommandNames @("codex")) }
    "WorkBuddy" = @{ CommandNames=@("workbuddy"); ProcessNames=@("WorkBuddy"); InstallPaths=@((Join-SkillTrackerPath $localAppData "Programs" "WorkBuddy" "WorkBuddy.exe"),(Join-SkillTrackerPath $localAppData "WorkBuddy" "WorkBuddy.exe"),(Join-SkillTrackerPath $appData "WorkBuddy" "WorkBuddy.exe")) + @(Get-CommandInstallPaths -CommandNames @("workbuddy")) }
    "CodeBuddy" = @{ CommandNames=@("codebuddy"); ProcessNames=@("CodeBuddy"); InstallPaths=@((Join-SkillTrackerPath $localAppData "Programs" "CodeBuddy" "CodeBuddy.exe"),(Join-SkillTrackerPath $localAppData "CodeBuddy" "CodeBuddy.exe"),(Join-SkillTrackerPath $appData "CodeBuddy" "CodeBuddy.exe")) + @(Get-CommandInstallPaths -CommandNames @("codebuddy")) }
    "Qoder" = @{ CommandNames=@("qoder","qoder-cn","lingma"); ProcessNames=@("Qoder","Lingma"); InstallPaths=@((Join-SkillTrackerPath $localAppData "Programs" "Qoder" "Qoder.exe"),(Join-SkillTrackerPath $localAppData "Qoder" "Qoder.exe"),(Join-SkillTrackerPath $localAppData "Programs" "Lingma" "Lingma.exe"),(Join-SkillTrackerPath $localAppData "Lingma" "Lingma.exe")) + @(Get-CommandInstallPaths -CommandNames @("qoder","qoder-cn","lingma")) }
    "CodeGeeX" = @{ InstallPathPatterns=@(Get-EditorExtensionInstallPatterns -ExtensionIds @("AMiner.codegeex","aminer.codegeex","codegeex-research.codegeex-research")) }
    "Baidu Comate" = @{ InstallPathPatterns=@(Get-EditorExtensionInstallPatterns -ExtensionIds @("BaiduComate.BaiduComate","baiducomate.baiducomate")) }
    "Continue" = @{ InstallPathPatterns=@(Get-EditorExtensionInstallPatterns -ExtensionIds @("continue.continue")) }
    "Gemini CLI" = @{ CommandNames=@("gemini"); InstallPaths=@(Get-CommandInstallPaths -CommandNames @("gemini")) }
    "GitHub Copilot" = @{ InstallPathPatterns=@(Get-EditorExtensionInstallPatterns -ExtensionIds @("github.copilot-chat","github.copilot")) }
    "Goose" = @{ CommandNames=@("goose"); InstallPaths=@(Get-CommandInstallPaths -CommandNames @("goose")) }
    "Hermes" = @{ CommandNames=@("hermes"); ProcessNames=@("hermes"); InstallPaths=@((Join-SkillTrackerPath $userHome ".hermes" "bin" "hermes"),(Join-SkillTrackerPath $userHome ".hermes" "bin" "hermes.exe"),(Join-SkillTrackerPath $userHome ".hermes" "bin" "hermes.cmd")) + @(Get-CommandInstallPaths -CommandNames @("hermes")) }
    "DeepSeek Harness" = @{ CommandNames=@("dsh"); ProcessNames=@("dsh"); InstallPaths=@((Join-SkillTrackerPath $userHome ".dsh" "bin" "dsh"),(Join-SkillTrackerPath $userHome ".dsh" "bin" "dsh.cmd"),(Join-SkillTrackerPath $userHome ".dsh" "bin" "dsh.ps1")) + @(Get-CommandInstallPaths -CommandNames @("dsh")); InstallPathPatterns=@(Get-NpmPackageInstallPatterns -PackageNames @("@deepseek-ai/dsh")) }
    "JetBrains AI" = @{ InstallPathPatterns=@(Get-EditorExtensionInstallPatterns -ExtensionIds @("JetBrains.jetbrains-ai-assistant","jetbrains.jetbrains-ai-assistant")) }
    "Junie" = @{ CommandNames=@("junie"); InstallPaths=@((Join-SkillTrackerPath $userHome ".junie" "bin" "junie"),(Join-SkillTrackerPath $userHome ".junie" "bin" "junie.exe")) + @(Get-CommandInstallPaths -CommandNames @("junie")) }
    "Kilo Code" = @{ InstallPathPatterns=@(Get-EditorExtensionInstallPatterns -ExtensionIds @("kilocode.kilo-code","kilo-code.kilo-code")) }
    "OpenCode" = @{ CommandNames=@("opencode"); ProcessNames=@("opencode"); InstallPaths=@((Join-SkillTrackerPath $localAppData "Programs" "OpenCode" "opencode.exe"),(Join-SkillTrackerPath $localAppData "Programs" "OpenCode" "OpenCode.exe"),(Join-SkillTrackerPath $localAppData "Programs" "opencode" "opencode.exe"),(Join-SkillTrackerPath $localAppData "OpenCode" "opencode.exe"),(Join-SkillTrackerPath $localAppData "OpenCode" "OpenCode.exe"),(Join-SkillTrackerPath $userHome ".local" "bin" "opencode"),(Join-SkillTrackerPath $userHome ".opencode" "bin" "opencode")) + @(Get-CommandInstallPaths -CommandNames @("opencode")); InstallPathPatterns=@(Get-NpmPackageInstallPatterns -PackageNames @("opencode-ai","@opencode-ai/cli")) }
    "Qwen Code" = @{ CommandNames=@("qwen","qwen-code"); InstallPaths=@((Join-SkillTrackerPath $userHome ".qwen" "bin" "qwen"),(Join-SkillTrackerPath $userHome ".qwen" "bin" "qwen.cmd"),(Join-SkillTrackerPath $userHome ".qwen" "bin" "qwen-code")) + @(Get-CommandInstallPaths -CommandNames @("qwen","qwen-code")) }
    "Roo Code" = @{ InstallPathPatterns=@(Get-EditorExtensionInstallPatterns -ExtensionIds @("rooveterinaryinc.roo-cline","roocode.roo-cline","roo-cline.roo-cline")) }
    "Sourcegraph Cody" = @{ InstallPathPatterns=@(Get-EditorExtensionInstallPatterns -ExtensionIds @("sourcegraph.cody-ai","sourcegraph.cody")) }
    "Tabby" = @{ InstallPathPatterns=@(Get-EditorExtensionInstallPatterns -ExtensionIds @("TabbyML.vscode-tabby","tabbyml.vscode-tabby")) }
    "Tabnine" = @{ InstallPathPatterns=@(Get-EditorExtensionInstallPatterns -ExtensionIds @("TabNine.tabnine-vscode","tabnine.tabnine-vscode")); InstallPaths=@((Join-SkillTrackerPath $userHome ".tabnine" "TabNine.exe"),(Join-SkillTrackerPath $userHome ".tabnine" "tabnine.exe"),(Join-SkillTrackerPath $appData "TabNine" "TabNine.exe"),(Join-SkillTrackerPath $appData "Tabnine" "Tabnine.exe")) }
}
foreach ($tool in $AUTO_DETECT_TOOLS) {
    if ($null -eq $tool.RequireInstall) { $tool.RequireInstall = $true }
    if ($toolInstallPolicies.ContainsKey($tool.Name)) {
        foreach ($property in $toolInstallPolicies[$tool.Name].Keys) {
            $tool[$property] = $toolInstallPolicies[$tool.Name][$property]
        }
    }
}

function Test-ToolInstalled {
    param([hashtable]$Tool)

    if ($Tool.ContainsKey("RequireInstall") -and -not $Tool.RequireInstall) {
        return [PSCustomObject]@{ Installed = $true; Reason = "log_source_allowed" }
    }

    foreach ($path in @($Tool.InstallPaths)) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return [PSCustomObject]@{ Installed = $true; Reason = "install_marker" }
        }
    }
    foreach ($pattern in @($Tool.InstallPathPatterns)) {
        if (-not $pattern) { continue }
        $matches = @(Get-ChildItem -Path $pattern -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($matches.Count -gt 0) {
            return [PSCustomObject]@{ Installed = $true; Reason = "install_marker" }
        }
    }
    foreach ($commandName in @($Tool.CommandNames)) {
        if ($commandName -and (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            return [PSCustomObject]@{ Installed = $true; Reason = "command_available" }
        }
    }

    foreach ($processName in @($Tool.ProcessNames)) {
        if ($processName -and (Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
            return [PSCustomObject]@{ Installed = $true; Reason = "process_running" }
        }
    }
    return [PSCustomObject]@{ Installed = $false; Reason = "install_marker_missing" }
}

# A small, bounded candidate probe gives the dashboard a useful upgrade path
# for fast-moving agent tools without pretending that an arbitrary directory is
# an installed product. Candidates are reported only when a current executable,
# command, or process signal exists; stale logs alone are deliberately hidden.
$ADAPTIVE_CANDIDATES = @(
    @{ Name="Kiro"; Id="kiro"; Paths=@((Join-SkillTrackerPath $appData "Kiro" "logs"),(Join-SkillTrackerPath $appData "Kiro" "User" "workspaceStorage"),(Join-SkillTrackerPath $userHome ".kiro" "sessions"),(Join-SkillTrackerPath $userHome ".kiro" "logs")); RequireInstall=$true; InstallPaths=@((Join-SkillTrackerPath $localAppData "Programs" "Kiro" "Kiro.exe"),(Join-SkillTrackerPath $localAppData "Kiro" "Kiro.exe")); CommandNames=@("kiro"); ProcessNames=@("Kiro"); TsField="timestamp" },
    @{ Name="OpenClaw"; Id="openclaw"; Paths=@((Join-SkillTrackerPath $userHome ".openclaw" "sessions"),(Join-SkillTrackerPath $userHome ".openclaw" "logs"),(Join-SkillTrackerPath $appData "OpenClaw" "logs"),(Join-SkillTrackerPath $localAppData "OpenClaw" "logs")); RequireInstall=$true; InstallPaths=@((Join-SkillTrackerPath $userHome ".openclaw" "bin" "openclaw"),(Join-SkillTrackerPath $userHome ".openclaw" "bin" "openclaw.cmd")) + @(Get-CommandInstallPaths -CommandNames @("openclaw")); CommandNames=@("openclaw"); ProcessNames=@("openclaw"); TsField="timestamp" },
    @{ Name="Pi Agent"; Id="pi-agent"; Paths=@((Join-SkillTrackerPath $userHome ".pi" "agent" "sessions"),(Join-SkillTrackerPath $userHome ".pi" "agent" "logs")); RequireInstall=$true; InstallPaths=@((Join-SkillTrackerPath $userHome ".local" "bin" "pi"),(Join-SkillTrackerPath $userHome ".pi" "bin" "pi")) + @(Get-CommandInstallPaths -CommandNames @("pi")); CommandNames=@("pi"); TsField="timestamp" },
    @{ Name="OpenHands"; Id="openhands"; Paths=@((Join-SkillTrackerPath $userHome ".openhands" "sessions"),(Join-SkillTrackerPath $userHome ".openhands" "logs"),(Join-SkillTrackerPath $appData "OpenHands" "logs")); RequireInstall=$true; InstallPaths=@((Join-SkillTrackerPath $userHome ".openhands" "bin" "openhands")) + @(Get-CommandInstallPaths -CommandNames @("openhands")); CommandNames=@("openhands"); ProcessNames=@("openhands"); TsField="timestamp" }
)
$script:unknownToolCandidates = @()

function Find-UnregisteredToolCandidates {
    $candidates = @()
    $knownNames = @($AUTO_DETECT_TOOLS | ForEach-Object { [string]$_.Name })
    foreach ($candidate in $ADAPTIVE_CANDIDATES) {
        if ($candidate.Name -in $knownNames) { continue }
        $presence = Test-ToolInstalled -Tool $candidate
        if (-not $presence.Installed) { continue }
        $existingLogRoots = @($candidate.Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
        $candidates += [PSCustomObject]@{
            name = [string]$candidate.Name
            profile_id = [string]$candidate.Id
            status = "installed_unadapted"
            install_reason = [string]$presence.Reason
            log_roots = $existingLogRoots
            recommendation = "检测到安装证据，但当前版本还没有稳定的日志适配器；可先用 custom_tools 指定会话目录。"
        }
    }
    return @($candidates)
}

$sourceReports = [System.Collections.Generic.List[PSCustomObject]]::new()
$sourceReportByKey = @{}

function Add-SourceReport {
    param(
        [string]$ToolName,
        [string]$Path,
        [string]$SourceType,
        [bool]$Installed = $true,
        [string]$InstallReason = "log_source_allowed"
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
            path_exists     = [bool]$exists
            installed       = [bool]$Installed
            install_reason  = $InstallReason
            detected        = [bool]($exists -and $Installed)
            path_kind       = if ($exists) { if (Test-Path -LiteralPath $Path -PathType Leaf) { "file" } else { "directory" } } else { "missing" }
            files_scanned   = 0
            files_with_hits = 0
            raw_hits        = 0
            dedup_hits      = 0
            read_errors     = 0
            latest_log_at   = ""
            latest_hit_at   = ""
            status          = if (-not $Installed) { "missing" } elseif ($exists) { "detected" } else { "missing" }
            status_reason   = if (-not $Installed) { "tool_not_installed" } elseif ($exists) { "path_detected" } else { "path_missing" }
        }
        $sourceReports.Add($report)
        $sourceReportByKey[$sourceKey] = $report
    }
    return $sourceReportByKey[$sourceKey]
}

$activeSources = [System.Collections.Generic.List[hashtable]]::new()
$activeSourceKeys = @{}
function Get-ActiveSourceFingerprint {
    $sourceFingerprint = ($activeSources | ForEach-Object { "$($_.Name)|$($_.Root)|$($_.TsField)" }) -join "`n"
    $candidateFingerprint = @($script:unknownToolCandidates | ForEach-Object {
        $roots = @($_.log_roots) -join "|"
        "candidate|$($_.name)|$($_.status)|$($_.install_reason)|$roots"
    }) -join "`n"
    return $sourceFingerprint + "`n" + $candidateFingerprint
}

function Refresh-ActiveSources {
    param([switch]$Quiet)

    $activeSources.Clear()
    $activeSourceKeys.Clear()
    $sourceReports.Clear()
    $sourceReportByKey.Clear()
    $script:unknownToolCandidates = @(Find-UnregisteredToolCandidates)

    foreach ($tool in $AUTO_DETECT_TOOLS) {
        $presence = Test-ToolInstalled -Tool $tool
        foreach ($p in $tool.Paths) {
            $report = Add-SourceReport -ToolName $tool.Name -Path $p -SourceType "auto" -Installed $presence.Installed -InstallReason $presence.Reason
            if ($report -and $report.detected) {
                $resolvedPath = $report.path
                $sourceKey = "$($tool.Name)|$resolvedPath"
                if (-not $activeSourceKeys.ContainsKey($sourceKey)) {
                    $activeSources.Add(@{ Name=$tool.Name; Root=$resolvedPath; TsField=$tool.TsField })
                    $activeSourceKeys[$sourceKey] = $true
                    if (-not $Quiet) { Write-Host "  [FOUND] $($tool.Name)  ->  $resolvedPath" }
                }
            }
        }
    }
    foreach ($ct in $cfg.custom_tools) {
        if (-not $ct.path) { continue }
        $customName = if ($ct.name) { [string]$ct.name } else { "CustomTool" }
        $customPath = Resolve-ConfiguredPath -Path ([string]$ct.path)
        $report = Add-SourceReport -ToolName $customName -Path $customPath -SourceType "custom" -Installed $true -InstallReason "configured_custom_source"
        if ($report -and $report.detected) {
            $resolvedPath = $report.path
            $sourceKey = "$customName|$resolvedPath"
            if (-not $activeSourceKeys.ContainsKey($sourceKey)) {
                $activeSources.Add(@{ Name=$customName; Root=$resolvedPath; TsField="timestamp" })
                $activeSourceKeys[$sourceKey] = $true
                if (-not $Quiet) { Write-Host "  [CUSTOM] $customName  ->  $resolvedPath" }
            }
        }
    }
    if (-not $Quiet -and $activeSources.Count -eq 0) {
        Write-Warning "No AI tools detected. Writing an empty local scan report."
    }
    return Get-ActiveSourceFingerprint
}

# Keep the previous published set separate from the static profile catalog.
# Older reports used `summary.supported_tools` for every built-in candidate, so
# migration first prefers detected rows and only then falls back to the newer
# discovery fields. This makes a removed tool visible in the radar as a
# transition without keeping it in the current tool list.
$toolNameAliases = @{
    "opencode" = "OpenCode"
    "deepseekharness" = "DeepSeek Harness"
    "deepseek-harness" = "DeepSeek Harness"
    "dsh" = "DeepSeek Harness"
    "workbuddy" = "WorkBuddy"
    "codebuddy" = "CodeBuddy"
    "qoder" = "Qoder"
    "qoder-cn" = "Qoder"
    "lingma" = "Qoder"
    "tongyi lingma" = "Qoder"
    "通义灵码" = "Qoder"
    "codegeex" = "CodeGeeX"
    "comate" = "Baidu Comate"
    "baiducomate" = "Baidu Comate"
    "文心快码" = "Baidu Comate"
}
function Get-CanonicalToolName {
    param([string]$Name)
    $value = [string]$Name
    if (-not $value) { return "" }
    $key = $value.Trim().ToLowerInvariant()
    if ($toolNameAliases.ContainsKey($key)) { return [string]$toolNameAliases[$key] }
    return $value.Trim()
}

function Get-ReportCurrentToolNames {
    param([object]$Report)

    if (-not $Report) { return @() }
    $names = @()
    if ($Report.discovery -and $Report.discovery.installed_tools) {
        $names = @($Report.discovery.installed_tools | ForEach-Object { Get-CanonicalToolName ([string]$_) })
    } elseif ($Report.summary -and $Report.summary.installed_tools) {
        $names = @($Report.summary.installed_tools | ForEach-Object { Get-CanonicalToolName ([string]$_) })
    } elseif ($Report.sources) {
        $names = @($Report.sources | Where-Object { $_.detected } | ForEach-Object { Get-CanonicalToolName ([string]$_.tool) })
    } elseif ($Report.tools) {
        $names = @($Report.tools | Where-Object { $_.status -and $_.status -ne "missing" } | ForEach-Object { Get-CanonicalToolName ([string]$_.tool) })
    }
    return @($names | Where-Object { $_ } | Sort-Object -Unique)
}

$toolReportJsonPath = Join-Path $cfg.output_dir "tool_report.json"
$lastPublishedToolNames = @()
if (Test-Path -LiteralPath $toolReportJsonPath -PathType Leaf) {
    try {
        $previousToolReport = Get-Content -LiteralPath $toolReportJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $lastPublishedToolNames = @(Get-ReportCurrentToolNames -Report $previousToolReport)
    } catch {
        Write-Warning "Could not read the previous tool report; discovery transition history starts fresh."
    }
}

$activeSourceFingerprint = Refresh-ActiveSources

# Acquire the watcher singleton before loading the skill catalog. A second
# desktop launch should exit immediately instead of repeating the expensive
# metadata scan before it discovers that another watcher owns the output.
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

$pidPath = Join-Path $cfg.output_dir ".collector.pid"
$heartbeatPath = Join-Path $cfg.output_dir ".collector-heartbeat.json"
$triggerPath = Join-Path $cfg.output_dir ".collector.trigger"
$cachePath = Join-Path $cfg.output_dir ".collector-cache.json"
$collectorCacheVersion = 4
$heartbeatMaxAgeSeconds = 90
$heartbeatIntervalSeconds = 5
$watcherMutex = $null
$ownsWatcherMutex = $false

$script:watcherStartedAt = ""
$script:watcherLastSuccessfulScanAt = ""
$script:watcherLastScanAt = ""
$script:watcherLastError = ""
$script:watcherNextHeartbeatAt = [DateTimeOffset]::UtcNow
function Write-CollectorHeartbeat {
    param(
        [string]$Status = "idle",
        [string]$ErrorMessage = ""
    )
    if (-not $Watch) { return }
    $now = [DateTimeOffset]::UtcNow
    if ($ErrorMessage) { $script:watcherLastError = $ErrorMessage }
    $payload = [ordered]@{
        version                  = 1
        pid                      = [int]$PID
        output_dir               = [System.IO.Path]::GetFullPath($cfg.output_dir)
        status                   = $Status
        started_at               = [string]$script:watcherStartedAt
        updated_at               = $now.ToString("o")
        last_scan_at             = [string]$script:watcherLastScanAt
        last_successful_scan_at  = [string]$script:watcherLastSuccessfulScanAt
        last_error               = [string]$script:watcherLastError
    }
    try {
        $tempPath = "$heartbeatPath.tmp"
        [System.IO.File]::WriteAllText($tempPath, ($payload | ConvertTo-Json -Depth 5 -Compress), [System.Text.Encoding]::UTF8)
        Move-Item -LiteralPath $tempPath -Destination $heartbeatPath -Force
        $script:watcherNextHeartbeatAt = $now.AddSeconds($heartbeatIntervalSeconds)
    } catch {
        # Heartbeat failure must not take down the collector; the launcher will
        # still use PID/process validation and can report a stale status.
    }
}

function Write-CollectorHeartbeatIfDue {
    if ($Watch -and [DateTimeOffset]::UtcNow -ge $script:watcherNextHeartbeatAt) {
        Write-CollectorHeartbeat -Status "scanning"
    }
}

function Remove-CollectorLease {
    if (-not $Watch) { return }
    $pidBelongsToCurrent = $false
    if (Test-Path -LiteralPath $pidPath -PathType Leaf) {
        $pidBelongsToCurrent = ((Get-Content -LiteralPath $pidPath -Raw -ErrorAction SilentlyContinue).Trim() -eq [string]$PID)
    }
    if ($pidBelongsToCurrent) {
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    }
    $heartbeat = $null
    if (Test-Path -LiteralPath $heartbeatPath -PathType Leaf) {
        try { $heartbeat = Get-Content -LiteralPath $heartbeatPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    if ($heartbeat -and [string]$heartbeat.pid -eq [string]$PID) {
        Remove-Item -LiteralPath $heartbeatPath -Force -ErrorAction SilentlyContinue
    }
}

if ($Watch) {
    $mutexHash = Get-StableId ([System.IO.Path]::GetFullPath($cfg.output_dir).ToLowerInvariant())
    $mutexName = if ($runningOnWindows) { "Local\SkillTrackerCollector_$mutexHash" } else { "SkillTrackerCollector_$mutexHash" }
    $watcherMutex = [System.Threading.Mutex]::new($false, $mutexName)
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
    $script:watcherStartedAt = [DateTimeOffset]::UtcNow.ToString("o")
    Write-CollectorHeartbeat -Status "starting"
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
$skillPathRx = [System.Text.RegularExpressions.Regex]'(?i)(?<path>(?<![A-Za-z0-9])(?:[A-Za-z]:|(?<!\\)[/\\](?!u[0-9a-f]{4}))[^"\r\n]*?skills(?:[/\\]|\\\\)+(?<skill>[A-Za-z0-9\-_]+)(?:[/\\]|\\\\)+SKILL\.md)'
$claudeAttributionSkillRx = [System.Text.RegularExpressions.Regex]'"attributionSkill"\s*:\s*"([^"]+)"'
$slashSkillRx = [System.Text.RegularExpressions.Regex]'(?m)^\s*/([A-Za-z0-9][A-Za-z0-9:_\-]*)(?=\s|$)'
$commandNameSkillRx = [System.Text.RegularExpressions.Regex]'(?is)<command-name>\s*/([A-Za-z0-9][A-Za-z0-9:_\-]*)\s*</command-name>'
$userRequestRx = [System.Text.RegularExpressions.Regex]'(?is)<USER_REQUEST>\s*(.*?)\s*</USER_REQUEST>'
$directSkillViewPathRx = [System.Text.RegularExpressions.Regex]'(?im)^\s*File Path:\s*`?(?:file:)?[^`\r\n]*[/\\]SKILL\.md`?\s*$'
$directSkillViewPathExtractRx = [System.Text.RegularExpressions.Regex]'(?im)^\s*File Path:\s*`?(?:file:)?(?<path>[^`\r\n]*[/\\]SKILL\.md)`?\s*$'
$timeRx   = [System.Text.RegularExpressions.Regex]'"(?:created_at|timestamp|time)"\s*:\s*"([^"]+)"'
$unixRx   = [System.Text.RegularExpressions.Regex]'"(?:created_at|timestamp|time|ts)"\s*:\s*(\d{9,13})'
$epoch    = ([datetimeoffset]::Parse('1970-01-01T00:00:00Z')).ToUniversalTime()
$maxSignalLineChars = 131072
$logReadChunkChars = 8192
$logLineOverlapChars = 8192

$logEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
$rawSeen = @{}
$dedupSeen = @{}

# JSONL files emitted by agent clients can contain a single very large JSON
# record (for example, a tool result with an embedded skill inventory). Do not
# call StreamReader.ReadLine() here: ReadLine allocates the entire record before
# the old 128 KiB safety bound can run. The reader below keeps only a bounded
# prefix/suffix plus the small overlap needed for regexes crossing chunks.
function New-LogReaderState {
    return @{
        Buffer      = New-Object char[] $logReadChunkChars
        BufferIndex = 0
        BufferCount = 0
        EndOfStream = $false
    }
}

function New-LogLineState {
    return @{
        Prefix              = [System.Text.StringBuilder]::new()
        SuffixChunks        = [System.Collections.Generic.LinkedList[string]]::new()
        SuffixLength        = 0
        ScanTail            = ""
        Length              = 0
        SawContent          = $false
        IsGenerated         = $false
        HasReadMarker       = $false
        HasUserInput        = $false
        Timestamp           = ""
        SkillNames          = [System.Collections.Generic.List[string]]::new()
        SkillPaths          = [System.Collections.Generic.List[PSCustomObject]]::new()
        PathKeys            = @{}
    }
}

function Add-LogLineSkillName {
    param(
        [hashtable]$State,
        [string]$Skill
    )
    if ($Skill -and -not $State.SkillNames.Contains($Skill)) {
        [void]$State.SkillNames.Add($Skill)
    }
}

function Add-LogLineSkillPath {
    param(
        [hashtable]$State,
        [string]$Skill,
        [string]$Path
    )
    if (-not $Skill -or -not $Path) { return }
    $normalizedPath = $Path.Replace('\\', '\').Trim()
    $key = "$Skill|$normalizedPath"
    if (-not $State.PathKeys.ContainsKey($key)) {
        $State.PathKeys[$key] = $true
        [void]$State.SkillPaths.Add([PSCustomObject]@{ skill = $Skill; path = $normalizedPath })
        Add-LogLineSkillName -State $State -Skill $Skill
    }
}

function Add-LogLineChunk {
    param(
        [hashtable]$State,
        [string]$Chunk
    )
    if ($null -eq $Chunk -or $Chunk.Length -eq 0) { return }
    $State.SawContent = $true
    $State.Length += $Chunk.Length

    $prefixRemaining = $maxSignalLineChars - $State.Prefix.Length
    if ($prefixRemaining -gt 0) {
        [void]$State.Prefix.Append($Chunk.Substring(0, [Math]::Min($prefixRemaining, $Chunk.Length)))
    }
    [void]$State.SuffixChunks.AddLast($Chunk)
    $State.SuffixLength += $Chunk.Length
    while ($State.SuffixLength -gt $maxSignalLineChars) {
        $firstNode = $State.SuffixChunks.First
        $excess = $State.SuffixLength - $maxSignalLineChars
        if ($excess -ge $firstNode.Value.Length) {
            $State.SuffixLength -= $firstNode.Value.Length
            [void]$State.SuffixChunks.RemoveFirst()
        } else {
            $firstNode.Value = $firstNode.Value.Substring($excess)
            $State.SuffixLength -= $excess
            break
        }
    }

    $scanText = if ($State.ScanTail) { $State.ScanTail + $Chunk } else { $Chunk }
    $State.ScanTail = if ($scanText.Length -gt $logLineOverlapChars) {
        $scanText.Substring($scanText.Length - $logLineOverlapChars)
    } else {
        $scanText
    }

    if (Test-GeneratedSkillInventoryLine -Line $scanText) {
        $State.IsGenerated = $true
    }
    $hasDshUserMessageToken = $scanText -match '(?i)"type"\s*:\s*"user/message"'
    $hasUserTypeToken = $scanText -match '(?i)"type"\s*:\s*"user"'
    $hasUserRoleToken = $scanText -match '(?i)"role"\s*:\s*"user"'
    if ($scanText -match '(?i)"type"\s*:\s*"USER_INPUT"' -or
        $hasDshUserMessageToken -or
        $hasUserTypeToken -or
        $hasUserRoleToken) {
        $State.HasUserInput = $true
    }
    $hasSkillFileToken = $scanText.Contains('SKILL.md')
    $hasReadMarkerToken = $scanText.Contains('[external_agent_tool_call: Read]') -or
        $scanText.Contains('"name":"Read"') -or
        $scanText.Contains('"name":"view_file"')
    if ($hasSkillFileToken -and -not $State.HasReadMarker) {
        $State.HasReadMarker = $hasReadMarkerToken -or
            ($scanText -match '(?i)\b(Get-Content|cat|type)\b[^\r\n]*SKILL\.md')
    } else {
        $State.HasReadMarker = $State.HasReadMarker -or $hasReadMarkerToken
    }

    # Avoid running several backtracking regexes over every JSON chunk. Most
    # chunks in a large transcript are ordinary text; only a chunk containing
    # a concrete skill/path/timestamp/command token needs semantic extraction.
    $hasStructuredSlashCommand = $scanText -match '(?i)"(?:text|content|message)"\s*:\s*"[^"\r\n]*\/[A-Za-z0-9]'
    $hasStructuredUserMessage = ($scanText -match '(?i)"type"\s*:\s*"message"') -and $hasUserRoleToken
    $hasCommandToken = $scanText.Contains('<command-name>') -or
        $scanText.Contains('<USER_REQUEST>') -or
        $scanText.Contains('"/') -or
        $hasDshUserMessageToken -or
        $hasStructuredSlashCommand -or
        $hasStructuredUserMessage
    $hasTimestampToken = $scanText.Contains('"created_at"') -or
        $scanText.Contains('"timestamp"') -or
        $scanText.Contains('"time"') -or
        $scanText.Contains('"ts"')
    $needsSemanticScan = $hasSkillFileToken -or $hasCommandToken -or
        ($State.Length -gt $maxSignalLineChars -and $hasTimestampToken)
    if ($needsSemanticScan) {
        if (-not $State.Timestamp) {
            $tm = $timeRx.Match($scanText)
            if ($tm.Success) {
                $State.Timestamp = $tm.Groups[1].Value
            } else {
                $um = $unixRx.Match($scanText)
                if ($um.Success) {
                    $unixMs = [long]$um.Groups[1].Value
                    if ($unixMs -gt 100000000000) { $unixMs = [long]($unixMs / 1000) }
                    $State.Timestamp = $epoch.AddSeconds($unixMs).ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
            }
        }

        foreach ($match in $skillPathRx.Matches($scanText)) {
            Add-LogLineSkillPath -State $State -Skill $match.Groups['skill'].Value -Path $match.Groups['path'].Value
        }
        foreach ($match in $directSkillViewPathExtractRx.Matches($scanText)) {
            $path = $match.Groups['path'].Value
            $skillDirectory = Split-Path -Parent $path
            $skillName = Split-Path -Leaf $skillDirectory
            Add-LogLineSkillPath -State $State -Skill $skillName -Path $path
        }
        if ($hasCommandToken) {
            Add-ChunkedExplicitSkillCommands -State $State -Text $scanText
        }
    }
}

function Add-ChunkedExplicitSkillCommands {
    param(
        [hashtable]$State,
        [string]$Text
    )
    if (-not $Text) { return }

    foreach ($match in $commandNameSkillRx.Matches($Text)) {
        $command = $match.Groups[1].Value
        if ($counts.ContainsKey($command)) { Add-LogLineSkillName -State $State -Skill $command }
    }
    foreach ($request in $userRequestRx.Matches($Text)) {
        foreach ($match in $slashSkillRx.Matches($request.Groups[1].Value)) {
            $command = $match.Groups[1].Value
            if ($counts.ContainsKey($command)) { Add-LogLineSkillName -State $State -Skill $command }
        }
    }
    if ($State.HasUserInput) {
        $structuredSlashRx = [System.Text.RegularExpressions.Regex]'(?i)"(?:text|content|message)"\s*:\s*"[^"\r\n]*?/(?<skill>[A-Za-z0-9][A-Za-z0-9:_-]*)(?=[\s"\\])'
        foreach ($match in $structuredSlashRx.Matches($Text)) {
            $command = $match.Groups['skill'].Value
            if ($counts.ContainsKey($command)) { Add-LogLineSkillName -State $State -Skill $command }
        }
    }
}

function Complete-LogLineState {
    param([hashtable]$State)

    $isTruncated = $State.Length -gt $maxSignalLineChars
    $suffixBuilder = [System.Text.StringBuilder]::new()
    foreach ($suffixChunk in $State.SuffixChunks) {
        [void]$suffixBuilder.Append($suffixChunk)
    }
    $suffixText = $suffixBuilder.ToString()
    $context = if ($isTruncated) {
        $State.Prefix.ToString() + "`n[skill-tracker truncated line context]`n" + $suffixText
    } else {
        $State.Prefix.ToString()
    }

    if ($isTruncated) {
        foreach ($contextPart in @($State.Prefix.ToString(), $suffixText, $State.ScanTail)) {
            Add-ChunkedExplicitSkillCommands -State $State -Text $contextPart
            if (-not $State.Timestamp) {
                $tm = $timeRx.Match($contextPart)
                if ($tm.Success) {
                    $State.Timestamp = $tm.Groups[1].Value
                } else {
                    $um = $unixRx.Match($contextPart)
                    if ($um.Success) {
                        $unixMs = [long]$um.Groups[1].Value
                        if ($unixMs -gt 100000000000) { $unixMs = [long]($unixMs / 1000) }
                        $State.Timestamp = $epoch.AddSeconds($unixMs).ToString("yyyy-MM-ddTHH:mm:ssZ")
                    }
                }
            }
        }
        if ($State.HasReadMarker) {
            foreach ($pathInfo in @($State.SkillPaths)) {
                Add-LogLineSkillName -State $State -Skill ([string]$pathInfo.skill)
            }
        }
    }

    return [PSCustomObject]@{
        Text          = $context
        IsEmpty       = -not $State.SawContent
        IsTruncated   = $isTruncated
        IsGenerated   = [bool]$State.IsGenerated
        Timestamp     = [string]$State.Timestamp
        SkillNames    = @($State.SkillNames)
        SkillPaths    = @($State.SkillPaths)
        LineHash      = Get-StableId ("$($State.Length)|$context")
    }
}

function Read-LogLineRecord {
    param(
        [System.IO.StreamReader]$Reader,
        [hashtable]$ReaderState
    )

    $lineState = New-LogLineState
    while ($true) {
        if ($ReaderState.BufferIndex -ge $ReaderState.BufferCount) {
            if ($ReaderState.EndOfStream) {
                if (-not $lineState.SawContent) { return $null }
                return Complete-LogLineState -State $lineState
            }
            $ReaderState.BufferCount = $Reader.ReadBlock($ReaderState.Buffer, 0, $ReaderState.Buffer.Length)
            $ReaderState.BufferIndex = 0
            Write-CollectorHeartbeatIfDue
            if ($ReaderState.BufferCount -le 0) {
                $ReaderState.EndOfStream = $true
                if (-not $lineState.SawContent) { return $null }
                return Complete-LogLineState -State $lineState
            }
        }

        $start = $ReaderState.BufferIndex
        $newline = [System.Array]::IndexOf(
            $ReaderState.Buffer,
            [char]10,
            $start,
            $ReaderState.BufferCount - $start
        )
        $ReaderState.BufferIndex = if ($newline -ge 0) { $newline } else { $ReaderState.BufferCount }

        $chunkLength = $ReaderState.BufferIndex - $start
        if ($chunkLength -gt 0) {
            Add-LogLineChunk -State $lineState -Chunk ([string]::new($ReaderState.Buffer, $start, $chunkLength))
        }
        if ($newline -ge 0) {
            $ReaderState.BufferIndex++
            return Complete-LogLineState -State $lineState
        }
    }
}

function Register-DiscoveredSkillSource {
    param(
        [string]$Skill,
        [string]$SkillPath
    )

    if (-not $Skill -or $script:counts.ContainsKey($Skill)) { return }
    if (-not $SkillPath -or -not (Test-Path -LiteralPath $SkillPath -PathType Leaf)) { return }

    $metadata = Get-SkillDocumentMetadata -Path $SkillPath
    $script:skillNames += $Skill
    $script:counts[$Skill] = 0
    $script:dedupCounts[$Skill] = 0
    $script:descs[$Skill] = [string]$metadata.description
    $script:skillSourcePaths[$Skill] = $SkillPath
    $script:skillMetadata[$Skill] = $metadata
}

function Ensure-DiscoveredSkill {
    param(
        [string]$Skill,
        [string]$Line,
        [string[]]$SkillPaths = @()
    )

    if (-not $Skill -or $script:counts.ContainsKey($Skill)) { return }
    foreach ($skillPath in @($SkillPaths)) {
        if (-not $skillPath) { continue }
        if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
            Register-DiscoveredSkillSource -Skill $Skill -SkillPath $skillPath
            return
        }
    }
    foreach ($pathMatch in $skillPathRx.Matches($Line)) {
        $skillPath = $pathMatch.Groups['path'].Value.Replace('\\', '\').Trim()
        if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) { continue }
        Register-DiscoveredSkillSource -Skill $Skill -SkillPath $skillPath
        return
    }
}

function Get-ToolLogFiles {
    param(
        [string]$Root,
        [string]$ToolName
    )
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return @() }

    $broadEditorTools = @("Cline", "Roo Code", "Kilo Code", "GitHub Copilot", "Sourcegraph Cody", "Amazon Q", "Augment", "Tabby", "Tabnine")
    $jsonMdTools = @("Aider", "Amp", "Goose", "OpenCode", "DeepSeek Harness", "WorkBuddy", "CodeBuddy", "Qoder", "CodeGeeX", "Baidu Comate", "Qwen Code", "Zed", "JetBrains AI", "Junie")
    $extensions = @(".jsonl")
    if ($ToolName -in @("Cursor", "Windsurf") -or $ToolName -in $broadEditorTools -or $ToolName -in $jsonMdTools -or $ToolName -notin (@("ClaudeCode", "Codex") + $transcriptTools)) {
        $extensions = @(".jsonl", ".json", ".log", ".txt")
    }
    if ($ToolName -in @("Aider", "Amp", "OpenCode", "DeepSeek Harness", "Qwen Code") -or $ToolName -in $broadEditorTools) {
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

    $hasDateFilter = $RecentDays -gt 0
    $cutoffUtc = if ($hasDateFilter) { (Get-Date).ToUniversalTime().AddDays(-1 * $RecentDays) } else { [DateTime]::MinValue }
    $hasLimit = $RecentFiles -gt 0

    if ($ToolName -in $transcriptTools) {
        $files = @(Get-ChildItem -Path $Root -Recurse -Filter "transcript.jsonl" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '(?i)[\\/]\.system_generated[\\/]logs[\\/]transcript\.jsonl$' -and (-not $hasDateFilter -or $_.LastWriteTimeUtc -ge $cutoffUtc) } |
            Sort-Object LastWriteTimeUtc -Descending)
        if ($hasLimit) { $files = @($files | Select-Object -First $RecentFiles) }
        return $files
    }

    if ($ToolName -eq "Aider") {
        $files = @(Get-ChildItem -Path $Root -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^\.aider\..*history(\.md)?$' -or
                $_.Name -eq ".aider.chat.history.md" -or
                $_.Name -eq ".aider.llm.history"
            } |
            Sort-Object LastWriteTimeUtc -Descending)
        if ($hasLimit) { $files = @($files | Select-Object -First $RecentFiles) }
        return $files
    }

    if ($ToolName -in @("JetBrains AI", "Junie")) {
        $files = @(Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                ($extensions -contains $_.Extension.ToLowerInvariant()) -and
                (-not $hasDateFilter -or $_.LastWriteTimeUtc -ge $cutoffUtc) -and
                ($_.FullName -match '(?i)([\\/]log[\\/]|ai-assistant|junie|matterhorn|\.junie)')
            } |
            Sort-Object LastWriteTimeUtc -Descending)
        if ($hasLimit) { $files = @($files | Select-Object -First $RecentFiles) }
        return $files
    }

    if ($ToolName -eq "GitHub Copilot" -and $Root -match '(?i)[\\/]workspaceStorage$') {
        $files = @(Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                ($extensions -contains $_.Extension.ToLowerInvariant()) -and
                (-not $hasDateFilter -or $_.LastWriteTimeUtc -ge $cutoffUtc) -and
                ($_.FullName -match '(?i)(github\.copilot|copilot-chat|chatSessions|chatEditingSessions)')
            } |
            Sort-Object LastWriteTimeUtc -Descending)
        if ($hasLimit) { $files = @($files | Select-Object -First $RecentFiles) }
        return $files
    }

    $files = @(Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            ($extensions -contains $_.Extension.ToLowerInvariant()) -and
            (-not $hasDateFilter -or $_.LastWriteTimeUtc -ge $cutoffUtc) -and
            (-not ($_.Name -eq "history.jsonl" -and $ToolName -in (@("ClaudeCode", "Codex") + $transcriptTools))) -and
            ($_.Name -ne "transcript_full.jsonl") -and
            ($_.Name -ne "workspace.json") -and
            ($_.Extension -notmatch '\.vscdb')
        } |
        Sort-Object LastWriteTimeUtc -Descending)
    if ($hasLimit) { $files = @($files | Select-Object -First $RecentFiles) }
    return $files
}

function Test-GeneratedSkillInventoryLine {
    param([string]$Line)
    return (
        $Line.Contains('"type":"function_call_output"') -or
        $Line.Contains('"type":"custom_tool_call_output"') -or
        $Line.Contains('<skills_instructions>') -or
        $Line.Contains('### Available skills') -or
        $Line.Contains('### Skill roots') -or
        $Line.Contains('"type":"skill_listing"')
    )
}

function Get-ExplicitSkillCommands {
    param([string]$Line)

    $mayContainUserCommand = $Line.Contains('<command-name>') -or
        $Line.Contains('<USER_REQUEST>') -or
        $Line.Contains('USER_INPUT') -or
        ($Line -match '(?i)"type"\s*:\s*"user/message"') -or
        (($Line -match '(?i)"type"\s*:\s*"message"') -and ($Line -match '(?i)"role"\s*:\s*"user"')) -or
        $Line.Contains('"type":"user"') -or
        ($Line -match '(?i)"type"\s*:\s*"user"') -or
        ($Line -match '(?i)"role"\s*:\s*"user"') -or
        ($Line.Contains('event_msg') -and $Line.Contains('user_message'))
    if (-not $mayContainUserCommand) { return @() }

    $texts = [System.Collections.Generic.List[string]]::new()
    try {
        $record = $Line | ConvertFrom-Json -ErrorAction Stop
        if ($record.type -eq 'USER_INPUT') {
            if ($record.content -is [string]) { [void]$texts.Add($record.content) }
            if ($record.text -is [string]) { [void]$texts.Add($record.text) }
        } elseif ($record.type -eq 'user/message') {
            $content = if ($record.data) { $record.data.content } else { $null }
            if ($content -is [string]) {
                [void]$texts.Add($content)
            } elseif ($content) {
                foreach ($part in @($content)) {
                    if ($part.text -is [string]) { [void]$texts.Add($part.text) }
                }
            }
            if ($record.data -and $record.data.text -is [string]) {
                [void]$texts.Add($record.data.text)
            }
        } elseif ($record.type -eq 'user') {
            if ($record.message.content -is [string]) { [void]$texts.Add($record.message.content) }
            if ($record.content -is [string]) { [void]$texts.Add($record.content) }
            if ($record.text -is [string]) { [void]$texts.Add($record.text) }
        } elseif ($record.type -eq 'message' -and $record.role -eq 'user') {
            if ($record.content -is [string]) {
                [void]$texts.Add($record.content)
            } elseif ($record.content) {
                foreach ($part in @($record.content)) {
                    if ($part.text -is [string]) { [void]$texts.Add($part.text) }
                    if ($part.content -is [string]) { [void]$texts.Add($part.content) }
                }
            }
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
    if ($Line.Contains('"type":"custom_tool_call_output"')) { return $false }
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

function Load-FileCache {
    $cache = @{}
    if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) { return $cache }
    try {
        $payload = Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$payload.version -ne $collectorCacheVersion -or -not $payload.entries) { return $cache }
        foreach ($property in $payload.entries.PSObject.Properties) {
            $entry = $property.Value
            $rawHits = @()
            foreach ($hit in @($entry.raw_hits)) {
                if ($hit -and $hit.skill) {
                    $rawHits += [PSCustomObject]@{
                        skill = [string]$hit.skill
                        ts = [string]$hit.ts
                        lineHash = [string]$hit.lineHash
                        sourcePath = [string]$hit.sourcePath
                    }
                }
            }
            $cache[$property.Name] = @{
                CacheVersion = $collectorCacheVersion
                LastWriteTimeUtc = ([datetime]$entry.last_write_time_utc).ToUniversalTime()
                Length = [long]$entry.length
                RawHits = $rawHits
                ReadStatus = "ok"
            }
        }
    } catch {
        Write-Warning "Could not load the collector file cache; changed files will be parsed normally."
    }
    return $cache
}

function Save-FileCache {
    $entries = [ordered]@{}
    foreach ($key in @($global:fileCache.Keys)) {
        $entry = $global:fileCache[$key]
        if (-not $entry -or $entry.CacheVersion -ne $collectorCacheVersion) { continue }
        $entries[$key] = [ordered]@{
            last_write_time_utc = ([datetime]$entry.LastWriteTimeUtc).ToUniversalTime().ToString("o")
            length = [long]$entry.Length
            raw_hits = @($entry.RawHits)
            read_status = if ($entry.ReadStatus) { [string]$entry.ReadStatus } else { "ok" }
        }
    }
    try {
        $tempPath = "$cachePath.tmp"
        $payload = [ordered]@{ version = $collectorCacheVersion; entries = $entries }
        [System.IO.File]::WriteAllText($tempPath, ($payload | ConvertTo-Json -Depth 8 -Compress), [System.Text.Encoding]::UTF8)
        Move-Item -LiteralPath $tempPath -Destination $cachePath -Force
    } catch {
        Write-Warning "Could not save the collector file cache."
    }
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

$global:fileCache = Load-FileCache
# A cached hit can be the only record that knows about a skill stored in a
# project-local .agents/skills directory. Restore that source before cached
# hits are filtered through the current skill inventory.
foreach ($entry in @($global:fileCache.Values)) {
    foreach ($hit in @($entry.RawHits)) {
        if ($hit -and $hit.sourcePath -and (Test-Path -LiteralPath $hit.sourcePath -PathType Leaf)) {
            Register-DiscoveredSkillSource -Skill ([string]$hit.skill) -SkillPath ([string]$hit.sourcePath)
        }
    }
}
$firstRun = $true
$skillFileStates = Get-SkillFilesState
$readFailureCount = 0
$readFailureFiles = [System.Collections.Generic.List[string]]::new()
$retryFileKeys = @{}

try {
    while ($true) {
    if ($Watch) {
        $previousSourceFingerprint = $activeSourceFingerprint
        $activeSourceFingerprint = Refresh-ActiveSources -Quiet
        $currentState = Get-LogFilesState
        $currentSkillState = Get-SkillFilesState
        $changed = $previousSourceFingerprint -ne $activeSourceFingerprint
        $skillsChanged = $false

        if (Test-Path -LiteralPath $triggerPath -PathType Leaf) {
            Remove-Item -LiteralPath $triggerPath -Force -ErrorAction SilentlyContinue
            $changed = $true
        }
        if ($ForceScan) {
            $changed = $true
            $ForceScan = $false
        }

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
            Write-CollectorHeartbeat -Status "idle"
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
        Write-CollectorHeartbeat -Status "scanning"
    }

    # Reset accumulator variables for clean scan
    $cacheHits = 0
    $parsedFiles = 0
    $readFailureCount = 0
    $readFailureFiles.Clear()
    $retryFileKeys = @{}
    $seenCacheKeys = @{}
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
        $sourceReport.read_errors = 0
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
        # Text logs are streamed line by line below. Do not skip a whole Codex
        # rollout merely because a long project conversation exceeded 10 MiB;
        # individual oversized lines are bounded before signal extraction.
        if ($f.Length -eq 0) { continue }
        $sessionId = ''
        $fileHitCount = 0
        $fileLatestHitUtc = $null
        if ($f.FullName -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
            $sessionId = $Matches[1]
        }

        # Query Cache
        $cacheKey = $f.FullName
        $seenCacheKeys[$cacheKey] = $true
        $cacheEntry = $global:fileCache[$cacheKey]
        $rawHits = @()
        $readSucceeded = $false
        $readErrorMessage = ""
        if ($cacheEntry -and $cacheEntry.CacheVersion -eq $collectorCacheVersion -and $cacheEntry.LastWriteTimeUtc -eq $f.LastWriteTimeUtc -and $cacheEntry.Length -eq $f.Length) {
            $rawHits = $cacheEntry.RawHits
            $cacheHits++
        } else {
            $parsedFiles++
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
                $readerState = New-LogReaderState
                while ($true) {
                    $record = Read-LogLineRecord -Reader $sr -ReaderState $readerState
                    if ($null -eq $record) { break }
                    Write-CollectorHeartbeatIfDue
                    if ($record.IsEmpty -or $record.IsGenerated) { continue }
                    $line = [string]$record.Text
                    $lineSkills = [System.Collections.Generic.List[string]]::new()

                    if ($record.IsTruncated) {
                        foreach ($skill in @($record.SkillNames)) {
                            if ($skill -and -not $lineSkills.Contains([string]$skill)) {
                                [void]$lineSkills.Add([string]$skill)
                            }
                        }
                    } else {
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
                    }

                    if ($lineSkills.Count -eq 0) { continue }

                    foreach ($skill in @($lineSkills | Select-Object -Unique)) {
                        $skillPathsForLine = @($record.SkillPaths |
                            Where-Object { $_.skill -eq $skill } |
                            Select-Object -ExpandProperty path)
                        Ensure-DiscoveredSkill -Skill $skill -Line $line -SkillPaths $skillPathsForLine
                    }

                    # Extract timestamp (ISO string first, then Unix epoch)
                    $ts = if ($record.IsTruncated) { [string]$record.Timestamp } else { '' }
                    if (-not $ts) {
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
                    }

                    $lineHash = if ($record.LineHash) { [string]$record.LineHash } else { Get-StableId $line }
                    foreach ($skill in @($lineSkills | Select-Object -Unique)) {
                        $rawHits += [PSCustomObject]@{
                            skill    = $skill
                            ts       = $ts
                            lineHash = $lineHash
                            sourcePath = if ($skillSourcePaths.ContainsKey($skill)) { [string]$skillSourcePaths[$skill] } else { "" }
                        }
                    }
                }
                $readSucceeded = $true
            } catch {
                $readErrorMessage = [string]$_.Exception.Message
            } finally {
                if ($sr) { $sr.Close() }
                elseif ($fs) { $fs.Close() }
            }
            if ($readSucceeded) {
                $global:fileCache[$cacheKey] = @{
                    CacheVersion = $collectorCacheVersion
                    LastWriteTimeUtc = $f.LastWriteTimeUtc
                    Length           = $f.Length
                    RawHits          = $rawHits
                    ReadStatus       = "ok"
                }
            } else {
                # A transient lock, delete, or decoding error is not an empty
                # successful scan. Keep the previous good cache entry (if any)
                # for this report, but leave its metadata unchanged so the next
                # watcher cycle retries the file.
                $readFailureCount++
                [void]$readFailureFiles.Add($f.FullName)
                $retryFileKeys[$cacheKey] = $true
                if ($sourceReport) { $sourceReport.read_errors++ }
                if ($cacheEntry -and $cacheEntry.CacheVersion -eq $collectorCacheVersion -and $cacheEntry.ReadStatus -eq "ok") {
                    $rawHits = @($cacheEntry.RawHits)
                } else {
                    $rawHits = @()
                }
                Write-Warning "Could not read log file; will retry next scan: $($f.FullName) ($readErrorMessage)"
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

foreach ($key in @($global:fileCache.Keys)) {
    if (-not $seenCacheKeys.ContainsKey($key)) {
        $global:fileCache.Remove($key)
    }
}
Save-FileCache
Write-Host "Cache: $cacheHits reused, $parsedFiles parsed"

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
$visibleToolReports = @($toolReports | Where-Object { $_.detected } | Sort-Object tool, path)
$knownToolNames = @($AUTO_DETECT_TOOLS | ForEach-Object { $_.Name } | Sort-Object -Unique)
$currentToolNames = @($activeSources | ForEach-Object { [string]$_.Name } | Where-Object { $_ } | Sort-Object -Unique)
$supportedToolNames = @($currentToolNames)
$newlyDetectedTools = @($currentToolNames | Where-Object { $_ -notin @($lastPublishedToolNames) })
$removedTools = @($lastPublishedToolNames | Where-Object { $_ -notin @($currentToolNames) } | Sort-Object -Unique)
$toolProfileByName = @{}
foreach ($profile in $AUTO_DETECT_TOOLS) {
    $toolProfileByName[[string]$profile.Name] = $profile
}
$toolSummaries = @()
foreach ($toolName in $supportedToolNames) {
    $rows = @($toolReports | Where-Object { $_.tool -eq $toolName })
    $detectedRows = @($rows | Where-Object { $_.detected })
    $files = [int](($detectedRows | Measure-Object files_scanned -Sum).Sum)
    $filesWithHits = [int](($detectedRows | Measure-Object files_with_hits -Sum).Sum)
    $raw = [int](($detectedRows | Measure-Object raw_hits -Sum).Sum)
    $dedup = [int](($detectedRows | Measure-Object dedup_hits -Sum).Sum)
    $readErrors = [int](($detectedRows | Measure-Object read_errors -Sum).Sum)
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
    $profile = $toolProfileByName[[string]$toolName]
    $profileId = if ($profile -and $profile.Id) {
        [string]$profile.Id
    } else {
        ([string]$toolName).ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    }
    $toolSummaries += [PSCustomObject]@{
        tool            = $toolName
        profile_id      = $profileId.Trim('-')
        publisher       = if ($profile -and $profile.Publisher) { [string]$profile.Publisher } else { "" }
        runtime_kind    = if ($profile -and $profile.RuntimeKind) { [string]$profile.RuntimeKind } else { "coding_tool" }
        aliases         = if ($profile -and $profile.Aliases) { @($profile.Aliases) } else { @() }
        provider_hints  = if ($profile -and $profile.ProviderHints) { @($profile.ProviderHints) } else { @() }
        status          = $status
        source_count    = $detectedRows.Count
        files_scanned   = $files
        files_with_hits = $filesWithHits
        raw_hits        = $raw
        dedup_hits      = $dedup
        read_errors     = $readErrors
        latest_log_at   = if ($latestLogAt) { [string]$latestLogAt[0] } else { "" }
        latest_hit_at   = if ($latestHitAt) { [string]$latestHitAt[0] } else { "" }
    }
}
$statusCounts = [ordered]@{
    ok            = @($toolSummaries | Where-Object { $_.status -eq "ok" }).Count
    no_skill_hits = @($toolSummaries | Where-Object { $_.status -eq "no_skill_hits" }).Count
    no_log_files  = @($toolSummaries | Where-Object { $_.status -eq "no_log_files" }).Count
    missing       = @($toolSummaries | Where-Object { $_.status -eq "missing" }).Count
    read_errors   = @($toolSummaries | Where-Object { $_.read_errors -gt 0 }).Count
}
$toolReportObj = [PSCustomObject]@{
    generated_at = $genAt
    build_id = $buildId
    summary = [PSCustomObject]@{
        supported_tools       = $supportedToolNames
        installed_tools        = $currentToolNames
        known_tools             = $knownToolNames
        skill_roots           = @($skillRoots)
        detected_source_count = $visibleToolReports.Count
        scanned_file_count    = [int](($toolReports | Measure-Object files_scanned -Sum).Sum)
        raw_hits              = [int](($toolReports | Measure-Object raw_hits -Sum).Sum)
        dedup_hits            = [int](($toolReports | Measure-Object dedup_hits -Sum).Sum)
        read_error_count      = $readFailureCount
        read_error_file_count = $readFailureFiles.Count
        status_counts         = [PSCustomObject]$statusCounts
    }
    discovery = [PSCustomObject]@{
        schema               = "skill-tracker-tool-discovery@1"
        mode                 = "local"
        platform             = $runtimePlatform
        scanned_at           = $genAt
        known_tool_count     = $knownToolNames.Count
        installed_tool_count = $currentToolNames.Count
        installed_tools      = $currentToolNames
        newly_detected_tools = $newlyDetectedTools
        removed_tools        = $removedTools
        hidden_tool_count    = [Math]::Max(0, $knownToolNames.Count - @($currentToolNames | Where-Object { $_ -in $knownToolNames }).Count)
        unknown_candidates   = @($script:unknownToolCandidates)
        scan_method          = "profile_registry+bounded_candidate_probe"
    }
    tools = $toolSummaries
    # `sources` retains non-detected diagnostics for troubleshooting. The UI
    # consumes `visible_sources`, so deleted tools do not remain on screen just
    # because an old log directory is still present.
    sources = $toolReports
    visible_sources = $visibleToolReports
}
$toolReportJsonPath = Join-Path $cfg.output_dir "tool_report.json"
[System.IO.File]::WriteAllText($toolReportJsonPath, ($toolReportObj | ConvertTo-Json -Depth 8), [System.Text.Encoding]::UTF8)
$toolReportJsPath = Join-Path $cfg.output_dir "tool_report.js"
$toolReportJson = $toolReportObj | ConvertTo-Json -Depth 8 -Compress
[System.IO.File]::WriteAllText($toolReportJsPath, "var TOOL_REPORT = $toolReportJson;`nvar BUILD_ID = $buildId;`n", [System.Text.Encoding]::UTF8)

# The next watcher cycle compares against this successful publication, not the
# original startup snapshot, so a persistent deletion is reported once.
$lastPublishedToolNames = @($currentToolNames)

if ($Watch -and $retryFileKeys.Count -gt 0) {
    # Do not let a transient read failure become the new watcher baseline.
    # Removing failed files forces the next cycle to notice and retry them even
    # when their mtime and length did not change after the failed read.
    foreach ($retryKey in @($retryFileKeys.Keys)) {
        [void]$fileStates.Remove($retryKey)
    }
}

$script:watcherLastScanAt = [DateTimeOffset]::UtcNow.ToString("o")
if ($readFailureCount -gt 0) {
    $script:watcherLastError = "Could not read $readFailureCount log file(s); retry scheduled."
    Write-CollectorHeartbeat -Status "degraded" -ErrorMessage $script:watcherLastError
} else {
    $script:watcherLastSuccessfulScanAt = $script:watcherLastScanAt
    $script:watcherLastError = ""
    Write-CollectorHeartbeat -Status "ready"
}

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
} catch {
    if ($Watch) {
        $script:watcherLastError = [string]$_.Exception.Message
        Write-CollectorHeartbeat -Status "error" -ErrorMessage $script:watcherLastError
    }
    throw
} finally {
    Remove-CollectorLease
    if ($watcherMutex) {
        if ($ownsWatcherMutex) {
            try { $watcherMutex.ReleaseMutex() } catch { }
        }
        $watcherMutex.Dispose()
    }
}
