param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,

    [Parameter(Mandatory = $true)]
    [string]$ChecksumPath
)

$ErrorActionPreference = "Stop"

$requiredFiles = @(
    "README.md",
    "LICENSE",
    "NOTICE",
    "SECURITY.md",
    "SUPPORT.md",
    "CONTRIBUTING.md",
    "CODE_OF_CONDUCT.md",
    "CITATION.cff",
    "START_HERE.md",
    "config.json",
    "collect.ps1",
    "run.bat",
    "start-dashboard.ps1",
    "dashboard/index.html",
    "dashboard/demo_data.js",
    "docs/ROADMAP.md",
    "scripts/verify-collector.ps1",
    "scripts/verify-portable-release.ps1"
)
$forbiddenFiles = @(
    "dashboard/skill_data.js",
    "dashboard/skill_log.js",
    "dashboard/skill_call_stats.json",
    "dashboard/skill_catalog.json",
    "dashboard/skill_catalog.js",
    "dashboard/tool_report.json",
    "dashboard/tool_report.js"
)

function Fail {
    param([string]$Message)

    Write-Error $Message
    exit 1
}

function Get-SafeArchiveEntryPath {
    param([string]$EntryName)

    if ([string]::IsNullOrWhiteSpace($EntryName)) {
        Fail "Release archive contains an empty entry path."
    }

    $normalizedSeparators = $EntryName -replace '\\', '/'
    if ($normalizedSeparators.StartsWith('/')) {
        Fail "Release archive entry must be relative: $EntryName"
    }

    $isDirectory = $normalizedSeparators.EndsWith('/')
    $pathForValidation = if ($isDirectory) {
        $normalizedSeparators.Substring(0, $normalizedSeparators.Length - 1)
    } else {
        $normalizedSeparators
    }
    $components = @($pathForValidation -split '/')
    $unsafeComponents = @($components | Where-Object {
        [string]::IsNullOrWhiteSpace($_) -or
        $_ -in @('.', '..') -or
        $_.EndsWith('.') -or
        $_.EndsWith(' ') -or
        $_ -match '[:<>"|?*]'
    })
    if ($components.Count -eq 0 -or $unsafeComponents.Count -gt 0) {
        Fail "Release archive contains an unsafe Windows path entry: $EntryName"
    }

    $safePath = $components -join '/'
    if ($isDirectory) { return "$safePath/" }
    return $safePath
}

if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
    Fail "Release archive not found: $ZipPath"
}
if (-not (Test-Path -LiteralPath $ChecksumPath -PathType Leaf)) {
    Fail "Checksum manifest not found: $ChecksumPath"
}

$archiveName = [System.IO.Path]::GetFileName($ZipPath)
$expectedHash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumEntry = Get-Content -LiteralPath $ChecksumPath -Encoding ASCII |
    Where-Object { $_ -match "^[a-fA-F0-9]{64}\s+\*?$([regex]::Escape($archiveName))$" } |
    Select-Object -First 1
if (-not $checksumEntry) {
    Fail "Checksum manifest has no SHA-256 entry for $archiveName"
}
$manifestHash = ($checksumEntry -split '\s+')[0].ToLowerInvariant()
if ($manifestHash -ne $expectedHash) {
    Fail "Checksum mismatch for $archiveName"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ZipPath).Path)
try {
    $allEntries = @($archive.Entries | ForEach-Object {
        Get-SafeArchiveEntryPath -EntryName $_.FullName
    })
    $entries = @($allEntries | Where-Object { -not $_.EndsWith('/') })
    $duplicateEntries = @($entries | Group-Object { $_.ToLowerInvariant() } | Where-Object { $_.Count -gt 1 })
    if ($duplicateEntries.Count -gt 0) {
        Fail ("Release archive contains colliding Windows entry paths: " + (($duplicateEntries | ForEach-Object { $_.Group -join ', ' }) -join '; '))
    }
    $topLevelNames = @($entries | ForEach-Object { ($_ -split '/')[0] } | Where-Object { $_ } | Sort-Object -Unique)
    if ($topLevelNames.Count -ne 1) {
        Fail "Release archive must contain exactly one top-level directory."
    }
    $topLevel = $topLevelNames[0]
    $relativeEntries = @($entries | ForEach-Object {
        if ($_.StartsWith("$topLevel/", [System.StringComparison]::OrdinalIgnoreCase)) { $_.Substring($topLevel.Length + 1) } else { "" }
    } | Where-Object { $_ })
    $relativeEntriesLower = @($relativeEntries | ForEach-Object { $_.ToLowerInvariant() })

    foreach ($requiredFile in $requiredFiles) {
        if ($relativeEntriesLower -notcontains $requiredFile.ToLowerInvariant()) {
            Fail "Release archive is missing required file: $requiredFile"
        }
    }
    foreach ($forbiddenFile in $forbiddenFiles) {
        if ($relativeEntriesLower -contains $forbiddenFile.ToLowerInvariant()) {
            Fail "Release archive contains private generated telemetry: $forbiddenFile"
        }
    }
    $vbsEntries = @($relativeEntries | Where-Object { $_ -match '(?i)\.vbs$' })
    if ($vbsEntries.Count -gt 0) {
        Fail ("Release archive contains unsupported VBS launchers: " + ($vbsEntries -join ', '))
    }
    $shortcutEntries = @($relativeEntries | Where-Object { $_ -match '(?i)\.lnk$' })
    if ($shortcutEntries.Count -gt 0) {
        Fail ("Release archive contains unsupported shortcut files: " + ($shortcutEntries -join ', '))
    }
} finally {
    $archive.Dispose()
}

Write-Host "Portable release contract passed: $archiveName"
