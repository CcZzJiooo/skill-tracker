# Start Here

Skill Tracker is designed to be opened quickly on Windows.

## Normal Users

Use the release package, not GitHub's auto-generated "Source code" download.

1. Download `skill-tracker-*-windows-portable.zip` from the GitHub release.
2. Unzip it anywhere, for example `Desktop\skill-tracker`.
3. Double-click `run.bat`.

The visible launcher first reads your local AI-agent logs and generates local dashboard data. It then opens the dashboard in your browser. Later, double-click `run.bat` again to refresh and open it.

If no supported local logs are found, the dashboard opens with an empty local scan report. Demo data is only a static fallback for inspecting the interface without running the launcher.

## Download Links

- GitHub Releases: https://github.com/CcZzJiooo/skill-tracker/releases
- GitHub source: https://github.com/CcZzJiooo/skill-tracker
- Gitee mirror: https://gitee.com/jiojio688/skill-tracker
- GitCode / AtomGit mirror: https://gitcode.com/2301_80046217/skill-tracker

For the easiest first run, use the GitHub release ZIP. The Gitee and GitCode mirrors are provided for domestic source browsing and backup access.

## Developers

```powershell
git clone https://github.com/CcZzJiooo/skill-tracker.git
cd skill-tracker
.\run.bat
```

Manual command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\collect.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-dashboard.ps1
```

## What This Project Is

Skill Tracker is a local-first observability tool:

- `collect.ps1` scans local AI-agent session logs.
- `dashboard/index.html` visualizes skill usage, Chinese descriptions, governance findings, and GitHub discovery.
- `run.bat` is the one-click Windows entry point.

It is not a single agent `skill`, because it observes and manages many skills across tools. It is not currently an `.exe`, because the project does not need an installer or background service.

## If Windows Blocks It

Right-click `run.bat`, choose **Properties**, and unblock it if Windows shows an unblock checkbox.

Or run this from PowerShell inside the project folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-dashboard.ps1
```

This portable package is unsigned. It does not require you to disable security software or add a blanket exclusion. If your organization blocks unsigned scripts, contact its IT administrator or use a future signed installer release.

## Privacy

Generated local telemetry stays on your machine and is ignored by Git:

- `dashboard/skill_data.js`
- `dashboard/skill_log.js`
- `dashboard/skill_call_stats.json`
- `dashboard/skill_catalog.json`
- `dashboard/skill_catalog.js`
- `dashboard/tool_report.json`
- `dashboard/tool_report.js`

Use the dashboard's anonymous export before sharing reports or screenshots publicly.
