param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$runningOnWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tracker-adaptive-launch-test-" + [guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $tempRoot "package"
$fakeHome = Join-Path $tempRoot "home"
$skillsRoot = Join-Path $fakeHome "skills"
$port = Get-Random -Minimum 29000 -Maximum 33000

function Copy-RequiredFile {
    param([string]$RelativePath)
    $source = Join-Path $repoRoot $RelativePath
    $destination = Join-Path $packageRoot $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

function Wait-ForText {
    param([string]$Path, [string]$Text, [int]$TimeoutSeconds = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            try {
                if ((Get-Content -LiteralPath $Path -Raw -Encoding UTF8).Contains($Text)) { return $true }
            } catch { }
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Wait-ForCandidate {
    param([string]$Path, [string]$Name, [int]$TimeoutSeconds = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            try {
                $report = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
                if (@($report.discovery.unknown_candidates | Where-Object { $_.name -eq $Name }).Count -gt 0) { return $true }
            } catch { }
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $false
}

try {
    foreach ($relativePath in @("collect.ps1", "start-dashboard.ps1", "dashboard/index.html", "dashboard/demo_data.js", "tools/platform-paths.psm1")) {
        Copy-RequiredFile -RelativePath $relativePath
    }
    $launcherText = Get-Content -LiteralPath (Join-Path $packageRoot "start-dashboard.ps1") -Raw -Encoding UTF8
    $scanBranchIndex = $launcherText.IndexOf('if ($NoWatch -and')
    $browserOpenIndex = $launcherText.IndexOf('Open-SkillTrackerBrowser -Url')
    if ($scanBranchIndex -lt 0 -or $browserOpenIndex -lt 0 -or $browserOpenIndex -lt $scanBranchIndex) {
        throw "The launcher must request or complete its scan before opening the dashboard browser."
    }
    New-Item -ItemType Directory -Path $skillsRoot -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $packageRoot "config.json"),
        (@{
            skills_root = ""
            skills_roots = @($skillsRoot)
            output_dir = "./dashboard"
            max_log_entries = 50
            dedup_window_minutes = 2
            custom_tools = @()
        } | ConvertTo-Json -Depth 5),
        [System.Text.Encoding]::UTF8
    )

    $priorUserProfile = $env:USERPROFILE
    $priorHome = $env:HOME
    $priorAppData = $env:APPDATA
    $priorLocalAppData = $env:LOCALAPPDATA
    try {
        $env:USERPROFILE = $fakeHome
        $env:HOME = $fakeHome
        $env:APPDATA = Join-Path $fakeHome "AppData\Roaming"
        $env:LOCALAPPDATA = Join-Path $fakeHome "AppData\Local"
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $packageRoot "start-dashboard.ps1") -Port $port -NoBrowser
        if ($LASTEXITCODE -ne 0) { throw "Initial launcher failed with code $LASTEXITCODE." }

        $reportPath = Join-Path $packageRoot "dashboard\tool_report.json"
        if (-not (Wait-ForText -Path $reportPath -Text '"discovery"')) {
            throw "Initial launch did not publish the adaptive discovery report."
        }

        $kiroDir = Join-Path $fakeHome "AppData\Local\Programs\Kiro"
        New-Item -ItemType Directory -Path $kiroDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $kiroDir "Kiro.exe") -Force | Out-Null

        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $packageRoot "start-dashboard.ps1") -Port $port -NoBrowser
        if ($LASTEXITCODE -ne 0) { throw "Second launcher did not reuse the running server." }
        if (-not (Wait-ForCandidate -Path $reportPath -Name "Kiro")) {
            throw "A tool installed between launches was not surfaced by the launch-time rescan."
        }
    } finally {
        $env:USERPROFILE = $priorUserProfile
        $env:HOME = $priorHome
        $env:APPDATA = $priorAppData
        $env:LOCALAPPDATA = $priorLocalAppData
    }

    Write-Host "Start-dashboard adaptive discovery test passed."
} finally {
    if ($runningOnWindows) {
        Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
            Where-Object { $_.CommandLine -and $_.CommandLine.Contains($packageRoot) } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
