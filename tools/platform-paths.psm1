function Join-SkillTrackerPath {
    param(
        [string]$Root,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ChildPath
    )

    if ([string]::IsNullOrWhiteSpace($Root)) { return $null }
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add($Root)
    foreach ($part in $ChildPath) {
        if (-not [string]::IsNullOrWhiteSpace($part)) { $parts.Add($part) }
    }
    return [System.IO.Path]::Combine([string[]]$parts)
}

function Get-SkillTrackerPlatformPaths {
    param(
        [ValidateSet("Windows", "Linux", "MacOS")]
        [string]$Platform,
        [Parameter(Mandatory = $true)]
        [string]$UserHome,
        [string]$AppData = "",
        [string]$LocalAppData = "",
        [string]$ProgramFiles = "",
        [string]$ProgramFilesX86 = ""
    )

    if (-not $Platform) {
        $Platform = if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
            "Windows"
        } elseif ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
            "MacOS"
        } else {
            "Linux"
        }
    }

    if ($Platform -eq "Windows") {
        if (-not $AppData) { $AppData = Join-SkillTrackerPath $UserHome "AppData" "Roaming" }
        if (-not $LocalAppData) { $LocalAppData = Join-SkillTrackerPath $UserHome "AppData" "Local" }
        $commonProgramRoots = @(
            (Join-SkillTrackerPath $LocalAppData "Programs"),
            $LocalAppData,
            $AppData,
            $ProgramFiles,
            $ProgramFilesX86
        ) | Where-Object { $_ } | Select-Object -Unique
    } elseif ($Platform -eq "MacOS") {
        if (-not $AppData) { $AppData = Join-SkillTrackerPath $UserHome "Library" "Application Support" }
        if (-not $LocalAppData) { $LocalAppData = $AppData }
        $commonProgramRoots = @(
            "/Applications",
            (Join-SkillTrackerPath $UserHome "Applications"),
            $AppData
        ) | Where-Object { $_ } | Select-Object -Unique
    } else {
        if (-not $AppData) {
            $AppData = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-SkillTrackerPath $UserHome ".config" }
        }
        if (-not $LocalAppData) {
            $LocalAppData = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-SkillTrackerPath $UserHome ".local" "share" }
        }
        $commonProgramRoots = @(
            (Join-SkillTrackerPath $UserHome ".local" "bin"),
            "/opt",
            "/usr/local/bin",
            $LocalAppData,
            $AppData
        ) | Where-Object { $_ } | Select-Object -Unique
    }

    $editorNames = @("Code", "Code - Insiders", "VSCodium", "Cursor", "Windsurf", "Trae", "Trae CN", "Qoder", "Qoder CN", "CodeBuddy")
    $globalRoots = @($editorNames | ForEach-Object {
        Join-SkillTrackerPath $AppData $_ "User" "globalStorage"
    })
    $workspaceRoots = @($editorNames | ForEach-Object {
        Join-SkillTrackerPath $AppData $_ "User" "workspaceStorage"
    })

    return [PSCustomObject]@{
        Platform = $Platform
        UserHome = $UserHome
        AppData = $AppData
        LocalAppData = $LocalAppData
        EditorGlobalStorageRoots = $globalRoots
        EditorWorkspaceStorageRoots = $workspaceRoots
        CommonProgramRoots = @($commonProgramRoots)
    }
}

Export-ModuleMember -Function Join-SkillTrackerPath, Get-SkillTrackerPlatformPaths
