# Start Here

Skill Tracker is designed to be opened quickly on Windows, Linux, and macOS.

## Normal Users

Use the release package, not GitHub's auto-generated "Source code" download.

1. Download `skill-tracker-*-portable.zip` from the GitHub release.
2. Unzip it anywhere.
3. Windows: double-click `run.bat` (or `创建桌面快捷方式.bat`).
4. Linux/macOS: install PowerShell 7, open a terminal in the extracted folder, and run `bash run.sh`.

The launcher reads your local AI-agent logs and generates local dashboard data. On Windows it can also create a `技能追踪器.lnk` shortcut and configure login startup. Those Windows integration controls are hidden on Linux and macOS.

If no supported local logs are found, the dashboard opens with an empty local scan report. Demo data is only a static fallback for inspecting the interface without running the launcher.

## Download Links

- GitHub Releases: https://github.com/CcZzJiooo/skill-tracker/releases
- GitHub source: https://github.com/CcZzJiooo/skill-tracker
- Gitee mirror: https://gitee.com/jiojio688/skill-tracker
- GitCode / AtomGit mirror: https://gitcode.com/2301_80046217/skill-tracker

For the easiest first run, use the GitHub release ZIP. Linux and macOS need PowerShell 7 (`pwsh`) on `PATH`; no Node.js or Python runtime is required for normal dashboard use. The Gitee and GitCode mirrors are provided for domestic source browsing and backup access.

## Developers

```text
git clone https://github.com/CcZzJiooo/skill-tracker.git
cd skill-tracker
# Windows: run.bat
# Linux/macOS: bash run.sh
```

Manual command:

```text
# Windows
powershell -NoProfile -ExecutionPolicy Bypass -File .\collect.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-dashboard.ps1

# Linux/macOS
pwsh -NoLogo -NoProfile -File ./collect.ps1
pwsh -NoLogo -NoProfile -File ./start-dashboard.ps1
```

## What This Project Is

Skill Tracker is a local-first observability tool:

- `collect.ps1` scans local AI-agent session logs.
- `dashboard/index.html` visualizes skill usage, Chinese descriptions, governance findings, and GitHub discovery.
- `run.bat` is the Windows entry point; `run.sh` is the Linux/macOS entry point.

It is not a single agent `skill`, because it observes and manages many skills across tools. It is not currently an `.exe`, because the project does not need an installer or background service.

## If Windows Blocks It

Right-click `run.bat`, choose **Properties**, and unblock it if Windows shows an unblock checkbox.

Or run this from PowerShell inside the project folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-dashboard.ps1
```

This portable package is unsigned. It does not require you to disable security software or add a blanket exclusion. If your organization blocks unsigned scripts, contact its IT administrator or use a future signed installer release.

## Privacy

Generated local telemetry stays on your machine and is ignored by Git. It is written to the configured `output_dir` (default: `dashboard/`):

- `dashboard/skill_data.js`
- `dashboard/skill_log.js`
- `dashboard/skill_call_stats.json`
- `dashboard/skill_catalog.json`
- `dashboard/skill_catalog.js`
- `dashboard/tool_report.json`
- `dashboard/tool_report.js`

Use the dashboard's anonymous export before sharing reports or screenshots publicly.
