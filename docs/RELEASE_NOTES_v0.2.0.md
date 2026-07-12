# Skill Tracker v0.2.0

> Superseded by v0.2.1. Download the latest Windows portable ZIP from GitHub Releases and run `run.bat`; the VBS launcher described below is no longer shipped or supported.

## Highlights

- Added a one-click Windows launcher (`启动看板.vbs`) that creates a `Skill Tracker Dashboard` desktop shortcut on first launch.
- Added a local no-cache dashboard server and one background collector watcher for live dashboard refreshes.
- Added a visible manual sync control with clear sync status feedback.
- Expanded source coverage reporting with scanned files, hit counts, and latest log activity.
- Improved recent-log scanning, file-read caching, and generated-data validation.

## Getting Started

1. Download and unzip `skill-tracker-v0.2.0-windows-portable.zip`.
2. Double-click `启动看板.vbs`.
3. Open the dashboard in the browser. Future launches can use the Desktop shortcut.

`run.bat` remains available if `.vbs` files are blocked by local policy.

## Privacy

The portable package excludes locally generated telemetry such as session IDs, paths, and collected call logs. Those files are generated only on the user's machine.
