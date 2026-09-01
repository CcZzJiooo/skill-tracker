param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$htmlPath = Join-Path $repoRoot "dashboard\index.html"
$html = Get-Content -LiteralPath $htmlPath -Raw -Encoding UTF8
$demoPath = Join-Path $repoRoot "dashboard\demo_data.js"
$demo = Get-Content -LiteralPath $demoPath -Raw -Encoding UTF8

$required = @(
    'data-view-button="tools"',
    'id="view-tools"',
    'id="toolRadarSummary"',
    'id="toolRadarCurrent"',
    'id="toolRadarChanges"',
    'id="toolRadarCandidates"',
    'function renderToolRadar()',
    'toolReport.visible_sources',
    'discovery.installed_tools',
    'discovery.removed_tools',
    'discovery.unknown_candidates',
    'OpenCode',
    'DeepSeek Harness'
)
foreach ($needle in $required) {
    if (-not $html.Contains($needle)) {
        throw "Dashboard tool radar contract is missing: $needle"
    }
}
foreach ($tool in @("WorkBuddy", "CodeBuddy", "Qoder", "CodeGeeX", "Baidu Comate")) {
    if (-not $demo.Contains($tool)) {
        throw "Dashboard demo data is missing mainstream tool coverage: $tool"
    }
}

$radarStart = $html.IndexOf("  function renderToolRadar()", [System.StringComparison]::Ordinal)
$radarEnd = $html.IndexOf("  function toolAuditStatus(", $radarStart, [System.StringComparison]::Ordinal)
if ($radarStart -lt 0 -or $radarEnd -le $radarStart) {
    throw "Could not isolate renderToolRadar for the legacy fallback contract."
}
$radarSource = $html.Substring($radarStart, $radarEnd - $radarStart)
if ($radarSource.Contains("reportSummary.supported_tools") -or $radarSource -match '(?m)^[^\S\r\n]+tools\s*\|\|') {
    throw "Tool radar must not resurrect legacy static supported_tools or skill-log tool names."
}

$scriptMatch = [System.Text.RegularExpressions.Regex]::Match($html, '(?s)<script>\s*(.*?)\s*</script>')
if (-not $scriptMatch.Success) { throw "Dashboard inline script was not found." }
$tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-dashboard-" + [guid]::NewGuid().ToString("N") + ".js")
try {
    [System.IO.File]::WriteAllText($tempScript, $scriptMatch.Groups[1].Value, [System.Text.Encoding]::UTF8)
    & node --check $tempScript
    if ($LASTEXITCODE -ne 0) { throw "Dashboard inline JavaScript syntax check failed." }
} finally {
    if (Test-Path -LiteralPath $tempScript) { Remove-Item -LiteralPath $tempScript -Force }
}

Write-Host "Dashboard adaptive tool radar contract passed."
