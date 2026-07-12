# Skill Tracker v0.2.1

## Windows Portable Hotfix

- Removed the VBS launcher and automatic desktop shortcut creation from the portable release.
- `run.bat` is now the single documented Windows entry point.
- The launcher completes one local log collection before opening the browser, so the first dashboard view uses collected local data rather than racing the demo fallback.
- The background watcher starts only after the initial scan. The launcher no longer force-terminates existing PowerShell processes.
- Added a SHA-256 manifest and portable-release contract verification to the build process.
- A first run without a standard skills directory now creates a truthful local scan report and retains skills discovered directly in supported logs.

## Download And Run

1. Download `skill-tracker-v0.2.1-windows-portable.zip` and `SHA256SUMS.txt` from GitHub Releases.
2. Optionally verify the ZIP hash against `SHA256SUMS.txt`.
3. Unzip the package and double-click `run.bat`.
4. Wait for the visible launcher to finish reading local logs. The browser then opens the dashboard.

The portable package remains unsigned. It reduces VBS-related heuristic alerts but cannot override organization-level execution policies or guarantee that every security product will show no prompt.
