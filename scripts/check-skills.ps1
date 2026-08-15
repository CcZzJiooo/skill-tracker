param([string]$Root = ".agents\skills")
$ErrorActionPreference = "Stop"
$resolved = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
$files = @(Get-ChildItem -LiteralPath $resolved -Recurse -Filter SKILL.md -File)
$errors = [System.Collections.Generic.List[string]]::new()
foreach ($file in $files) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    if ($text -notmatch '(?ms)^---\s*\r?\n.*?\bname\s*:') { [void]$errors.Add("$($file.FullName): missing frontmatter name") }
    if ($text -notmatch '(?ms)^---\s*\r?\n.*?\bdescription\s*:\s*\S') { [void]$errors.Add("$($file.FullName): missing frontmatter description") }
    if ($file.Length -lt 80) { [void]$errors.Add("$($file.FullName): SKILL.md is suspiciously short") }
}
if ($errors.Count) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }
Write-Host "Skill quality check passed: $($files.Count) SKILL.md files under $resolved."
