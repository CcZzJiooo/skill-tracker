param(
    [switch]$SkipCollect
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$dashboardDir = Join-Path $repoRoot "dashboard"

function Fail {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Read-JsAssignment {
    param(
        [string]$Path,
        [string]$Name
    )
    if (-not (Test-Path $Path)) { Fail "Missing generated file: $Path" }
    $prefix = "var $Name = "
    $line = Get-Content -LiteralPath $Path -Encoding UTF8 | Where-Object { $_.StartsWith($prefix) } | Select-Object -First 1
    if (-not $line) { Fail "Cannot find JS assignment: $Name in $Path" }
    $json = $line.Substring($prefix.Length).Trim()
    if ($json.EndsWith(";")) { $json = $json.Substring(0, $json.Length - 1) }
    $items = New-Object System.Collections.ArrayList
    foreach ($item in @($json | ConvertFrom-Json)) {
        [void]$items.Add($item)
    }
    return $items
}

function Read-JsValue {
    param(
        [string]$Path,
        [string]$Name
    )
    if (-not (Test-Path $Path)) { Fail "Missing generated file: $Path" }
    $prefix = "var $Name = "
    $line = Get-Content -LiteralPath $Path -Encoding UTF8 | Where-Object { $_.StartsWith($prefix) } | Select-Object -First 1
    if (-not $line) { Fail "Cannot find JS assignment: $Name in $Path" }
    $json = $line.Substring($prefix.Length).Trim()
    if ($json.EndsWith(";")) { $json = $json.Substring(0, $json.Length - 1) }
    return ($json | ConvertFrom-Json)
}

if (-not $SkipCollect) {
    & (Join-Path $repoRoot "collect.ps1")
    if (-not $?) { Fail "collect.ps1 failed." }
}

$skillDataPath = Join-Path $dashboardDir "skill_data.js"
$skillLogPath = Join-Path $dashboardDir "skill_log.js"
$toolReportPath = Join-Path $dashboardDir "tool_report.js"

$tools = @()
foreach ($tool in (Read-JsAssignment -Path $skillDataPath -Name "DETECTED_TOOLS")) { $tools += $tool }
$logs = @()
foreach ($row in (Read-JsAssignment -Path $skillLogPath -Name "SKILL_LOG")) { $logs += $row }
$toolReport = Read-JsValue -Path $toolReportPath -Name "TOOL_REPORT"
$sourceReports = @($toolReport.sources)
if (-not $sourceReports.Count) { Fail "TOOL_REPORT has no source coverage rows." }

$duplicateTools = @($tools | Group-Object | Where-Object { $_.Count -gt 1 })
if ($duplicateTools.Count) {
    Fail ("Duplicate detected tools: " + (($duplicateTools | ForEach-Object { $_.Name }) -join ", "))
}

$blankRows = @($logs | Where-Object { -not $_.skill -or -not $_.tool })
if ($blankRows.Count) { Fail "Found $($blankRows.Count) log rows with missing skill/tool." }

$unknownTools = @($logs | Where-Object { $tools -notcontains $_.tool } | Select-Object -ExpandProperty tool -Unique)
if ($unknownTools.Count) { Fail ("Log rows reference tools not in DETECTED_TOOLS: " + ($unknownTools -join ", ")) }

$detectedReportTools = @($sourceReports | Where-Object { $_.detected -eq $true } | Select-Object -ExpandProperty tool -Unique)
$toolsWithoutReport = @($tools | Where-Object { $detectedReportTools -notcontains $_ })
if ($toolsWithoutReport.Count) { Fail ("Detected tools missing source report rows: " + ($toolsWithoutReport -join ", ")) }

$badDetectedReports = @($sourceReports | Where-Object {
    $_.detected -eq $true -and $_.status -notin @("ok", "no_skill_hits", "no_log_files", "scanned")
})
if ($badDetectedReports.Count) { Fail "Found detected tool source rows with invalid status." }

$reportRawHits = [int](($sourceReports | Measure-Object raw_hits -Sum).Sum)
if ($reportRawHits -lt $logs.Count) {
    Fail "Tool report raw_hits ($reportRawHits) is lower than emitted log rows ($($logs.Count))."
}

$duplicateDedupKeys = @($logs | Where-Object { $_.dedup -eq $true } | Group-Object dedup_key | Where-Object { $_.Count -gt 1 })
if ($duplicateDedupKeys.Count) { Fail "Found $($duplicateDedupKeys.Count) duplicate dedup keys." }

$duplicateVisibleRows = @($logs | Group-Object tool, skill, time, session | Where-Object { $_.Count -gt 1 })
if ($duplicateVisibleRows.Count) { Fail "Found $($duplicateVisibleRows.Count) duplicate visible raw log rows." }

Write-Host ""
Write-Host "Collector verification passed."
Write-Host "Detected tools: $($tools -join ', ')"
Write-Host "Raw log rows: $($logs.Count)"
Write-Host "Tool source rows: $($sourceReports.Count)"
Write-Host "Scanned files: $([int](($sourceReports | Measure-Object files_scanned -Sum).Sum))"
Write-Host ""
Write-Host "Raw by tool:"
$rawByTool = @{}
$logs | Group-Object tool | ForEach-Object { $rawByTool[$_.Name] = $_.Count }
foreach ($tool in ($tools | Sort-Object)) {
    $count = if ($rawByTool.ContainsKey($tool)) { $rawByTool[$tool] } else { 0 }
    Write-Host ("  {0}: {1}" -f $tool, $count)
}
Write-Host ""
Write-Host "Dedup by tool:"
$dedupByTool = @{}
$logs | Where-Object { $_.dedup -eq $true } | Group-Object tool | ForEach-Object { $dedupByTool[$_.Name] = $_.Count }
foreach ($tool in ($tools | Sort-Object)) {
    $count = if ($dedupByTool.ContainsKey($tool)) { $dedupByTool[$tool] } else { 0 }
    Write-Host ("  {0}: {1}" -f $tool, $count)
}
