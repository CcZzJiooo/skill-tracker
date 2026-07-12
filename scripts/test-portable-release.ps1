param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$verifier = Join-Path $PSScriptRoot "verify-portable-release.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-portable-test-" + [guid]::NewGuid().ToString("N"))
$packageName = "skill-tracker-test-windows-portable"
$stageDir = Join-Path $tempRoot $packageName
$zipPath = Join-Path $tempRoot "$packageName.zip"
$checksumPath = Join-Path $tempRoot "SHA256SUMS.txt"

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Write-TextFile {
    param(
        [string]$Path,
        [string]$Content = "test"
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::UTF8)
}

function Write-Checksum {
    param(
        [string]$ArchivePath,
        [string]$ManifestPath
    )

    $hash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    [System.IO.File]::WriteAllText(
        $ManifestPath,
        "$hash *$([System.IO.Path]::GetFileName($ArchivePath))`n",
        [System.Text.Encoding]::ASCII
    )
}

function Add-RawZipEntry {
    param([string]$RelativePath)

    $archive = [System.IO.Compression.ZipFile]::Open(
        $zipPath,
        [System.IO.Compression.ZipArchiveMode]::Update
    )
    try {
        $entry = $archive.CreateEntry("$packageName/$RelativePath")
        $stream = $entry.Open()
        try {
            $writer = [System.IO.StreamWriter]::new($stream, [System.Text.Encoding]::UTF8)
            try {
                $writer.Write("test")
            } finally {
                $writer.Dispose()
            }
        } finally {
            $stream.Dispose()
        }
    } finally {
        $archive.Dispose()
    }
}

function Add-RawZipDirectory {
    param([string]$RelativePath)

    $archive = [System.IO.Compression.ZipFile]::Open(
        $zipPath,
        [System.IO.Compression.ZipArchiveMode]::Update
    )
    try {
        [void]$archive.CreateEntry("$packageName/$RelativePath")
    } finally {
        $archive.Dispose()
    }
}

function New-TestPackage {
    param(
        [switch]$IncludeVbs,
        [switch]$IncludeShortcut,
        [switch]$OmitVerifier,
        [string[]]$AdditionalEntries = @(),
        [string[]]$AdditionalDirectoryEntries = @()
    )

    if (Test-Path -LiteralPath $stageDir) {
        Remove-Item -LiteralPath $stageDir -Recurse -Force
    }
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

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

    foreach ($relativePath in $requiredFiles) {
        if ($OmitVerifier -and $relativePath -eq "scripts/verify-portable-release.ps1") { continue }
        Write-TextFile -Path (Join-Path $stageDir $relativePath)
    }
    if ($IncludeVbs) {
        Write-TextFile -Path (Join-Path $stageDir "launcher.vbs")
    }
    if ($IncludeShortcut) {
        Write-TextFile -Path (Join-Path $stageDir "launcher.lnk")
    }

    Compress-Archive -Path $stageDir -DestinationPath $zipPath -Force
    foreach ($relativePath in $AdditionalEntries) {
        Add-RawZipEntry -RelativePath $relativePath
    }
    foreach ($relativePath in $AdditionalDirectoryEntries) {
        Add-RawZipDirectory -RelativePath $relativePath
    }
    Write-Checksum -ArchivePath $zipPath -ManifestPath $checksumPath
}

try {
    New-TestPackage
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ZipPath $zipPath -ChecksumPath $checksumPath
    if ($LASTEXITCODE -ne 0) { throw "Portable release verifier rejected a valid package." }

    New-TestPackage -AdditionalDirectoryEntries @("dashboard/")
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ZipPath $zipPath -ChecksumPath $checksumPath
    if ($LASTEXITCODE -ne 0) { throw "Portable release verifier rejected a safe directory entry." }

    New-TestPackage -IncludeVbs
    $rejectedVbs = $false
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ZipPath $zipPath -ChecksumPath $checksumPath
        if ($LASTEXITCODE -ne 0) { $rejectedVbs = $true }
    } catch {
        $rejectedVbs = $true
    }
    if (-not $rejectedVbs) {
        throw "Portable release verifier accepted a package containing a VBS launcher."
    }

    New-TestPackage -IncludeShortcut
    $rejectedShortcut = $false
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ZipPath $zipPath -ChecksumPath $checksumPath
        if ($LASTEXITCODE -ne 0) { $rejectedShortcut = $true }
    } catch {
        $rejectedShortcut = $true
    }
    if (-not $rejectedShortcut) {
        throw "Portable release verifier accepted a package containing a shortcut."
    }

    New-TestPackage -OmitVerifier
    $rejectedMissingVerifier = $false
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ZipPath $zipPath -ChecksumPath $checksumPath
        if ($LASTEXITCODE -ne 0) { $rejectedMissingVerifier = $true }
    } catch {
        $rejectedMissingVerifier = $true
    }
    if (-not $rejectedMissingVerifier) {
        throw "Portable release verifier accepted a package without its verification script."
    }

    foreach ($unsafePath in @(
        "dashboard/./skill_data.js",
        "dashboard\.\skill_data.js",
        "dashboard/../dashboard/skill_data.js",
        "launcher.vbs.",
        "launcher.lnk ",
        "dashboard/INDEX.html"
    )) {
        New-TestPackage -AdditionalEntries @($unsafePath)
        $rejectedUnsafePath = $false
        try {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ZipPath $zipPath -ChecksumPath $checksumPath
            if ($LASTEXITCODE -ne 0) { $rejectedUnsafePath = $true }
        } catch {
            $rejectedUnsafePath = $true
        }
        if (-not $rejectedUnsafePath) {
            throw "Portable release verifier accepted unsafe Windows-normalized entry: $unsafePath"
        }
    }

    New-TestPackage -AdditionalDirectoryEntries @("dashboard/../outside/")
    $rejectedUnsafeDirectory = $false
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ZipPath $zipPath -ChecksumPath $checksumPath
        if ($LASTEXITCODE -ne 0) { $rejectedUnsafeDirectory = $true }
    } catch {
        $rejectedUnsafeDirectory = $true
    }
    if (-not $rejectedUnsafeDirectory) {
        throw "Portable release verifier accepted an unsafe Windows-normalized directory entry."
    }

    Write-Host "Portable release verification tests passed."
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
