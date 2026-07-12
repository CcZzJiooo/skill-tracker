param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$runBat = Join-Path $repoRoot "run.bat"
$content = Get-Content -LiteralPath $runBat -Raw -Encoding ASCII

if ($content -match '(?i)dashboard\\index\.html') {
    throw "run.bat must not open the demo dashboard when local collection cannot run."
}
if ($content -notmatch '(?i)PowerShell was not found\. Skill Tracker cannot read local logs without it\.') {
    throw "run.bat must explain why PowerShell is required."
}
if ($content -notmatch '(?i)pause\s*\r?\n\s*exit /b 1') {
    throw "run.bat must return a nonzero status after a failed launch."
}

Write-Host "run.bat contract test passed."
