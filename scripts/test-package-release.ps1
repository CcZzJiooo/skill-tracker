param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$packager = Join-Path $PSScriptRoot "package-release.ps1"
$verifier = Join-Path $PSScriptRoot "verify-portable-release.ps1"
$tempOutput = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-package-test-" + [guid]::NewGuid().ToString("N"))
$version = "v-test"
$secondVersion = "v-test-second"
$zipPath = Join-Path $tempOutput "skill-tracker-$version-windows-portable.zip"
$secondZipPath = Join-Path $tempOutput "skill-tracker-$secondVersion-windows-portable.zip"
$checksumPath = Join-Path $tempOutput "SHA256SUMS.txt"

try {
    $missingVersionRejected = $false
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $packager -OutputDir $tempOutput
        if ($LASTEXITCODE -ne 0) { $missingVersionRejected = $true }
    } catch {
        $missingVersionRejected = $true
    }
    if (-not $missingVersionRejected) {
        throw "Package release script accepted an omitted release version."
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $packager -Version $version -OutputDir $tempOutput
    if ($LASTEXITCODE -ne 0) {
        throw "Package release script exited with code $LASTEXITCODE."
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ZipPath $zipPath -ChecksumPath $checksumPath
    if ($LASTEXITCODE -ne 0) {
        throw "Package release output failed portable release verification."
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $packager -Version $secondVersion -OutputDir $tempOutput
    if ($LASTEXITCODE -ne 0) {
        throw "Package release script exited with code $LASTEXITCODE for the second version."
    }

    foreach ($archive in @($zipPath, $secondZipPath)) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ZipPath $archive -ChecksumPath $checksumPath
        if ($LASTEXITCODE -ne 0) {
            throw "Checksum manifest did not retain a valid entry for $([System.IO.Path]::GetFileName($archive))."
        }
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $packager -Version $version -OutputDir $tempOutput
    if ($LASTEXITCODE -ne 0) {
        throw "Package release script failed to rebuild the same release version."
    }
    $versionEntries = @(Get-Content -LiteralPath $checksumPath -Encoding ASCII | Where-Object {
        $_ -like "*$([System.IO.Path]::GetFileName($zipPath))"
    })
    if ($versionEntries.Count -ne 1) {
        throw "Checksum manifest retained $($versionEntries.Count) entries for a rebuilt release archive."
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ZipPath $zipPath -ChecksumPath $checksumPath
    if ($LASTEXITCODE -ne 0) {
        throw "Rebuilt release archive failed portable release verification."
    }

    Write-Host "Package release test passed."
} finally {
    if (Test-Path -LiteralPath $tempOutput) {
        Remove-Item -LiteralPath $tempOutput -Recurse -Force
    }
}
