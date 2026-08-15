# Skill Tracker v0.3.0

This release fixes local data freshness, startup scanning cost, installed-tool detection, and the manual synchronization workflow.

## User-visible fixes

- The dashboard Sync button now calls the local `/api/sync` endpoint. The endpoint queues a watcher scan and the page waits for a new build before reloading generated data.
- Normal startup reuses a healthy watcher and returns without waiting for a full historical scan. A first run still starts collection in the background and the dashboard refreshes after generated files appear.
- The watcher refreshes the active tool list on every cycle. A newly installed supported desktop tool becomes eligible without restarting the dashboard; a removed tool is removed from the active scan set.
- Deleted Trae, Cursor, Windsurf, Antigravity, and Zed installations no longer remain active only because old log directories are still present.
- Persistent file fingerprints reuse unchanged log parsing results across processes. Only new, modified, or newly discovered files are parsed again.
- Codex `response_item` and `custom_tool_call` records that read a local `SKILL.md` now resolve Windows paths correctly, including JSON escaped quotes, and preserve the record timestamp.
- Claude legacy `type=user` command records remain supported. Generated `custom_tool_call_output` records are excluded before attribution and file-read parsing to prevent false positives.
- The launcher no longer terminates an unrelated HTTP server when its port is occupied. It returns an explicit port-conflict error instead.
- `run.bat` now describes background synchronization and uses stable ASCII fallback messages so its PowerShell contract is readable on every Windows code page.

## Root causes

| Symptom | Root cause | Resolution |
| --- | --- | --- |
| Sync reported that data was current but counts did not move | The button only reloaded static JavaScript files; no collector work was requested | Added `/api/sync`, a trigger file, watcher polling, and build-id based reload detection |
| Desktop shortcut appeared to scan for a long time | Startup synchronously launched a full collector scan, and old watcher processes were reused | Startup now starts or reuses a background watcher; stale watchers older than `collect.ps1` are replaced |
| Trae continued to appear after uninstall | Source discovery treated an existing log directory as proof that the application was installed | Desktop tools now require an executable marker, PATH command, or running process; log residue alone is inactive |
| The dashboard stopped at an old date | Recent Codex records were not recognized consistently, and stale processes could overwrite new report formats | Added new Codex record/path handling and stale-writer prevention; generated dates come from the current scan |
| Repeat scans were expensive | Every process reparsed every unchanged log file | Added a versioned cache keyed by absolute path, size, and UTC write time |

## Collection behavior

The collector keeps configured custom tools available as explicit sources. Supported desktop applications use common Windows installation locations, PATH commands, and running-process checks. The watcher recomputes this state periodically, so installation and removal changes take effect without restarting the UI.

The generated files remain local:

- `dashboard/skill_data.js`
- `dashboard/skill_log.js`
- `dashboard/skill_catalog.js`
- `dashboard/tool_report.json`
- `dashboard/tool_report.js`

The cache and trigger files are local runtime artifacts and are ignored by Git:

- `dashboard/.collector-cache.json`
- `dashboard/.collector.trigger`

## Usage

1. Start the project with `run.bat` or `start-dashboard.ps1`.
2. On the first run, leave the dashboard open while the background watcher creates the generated files.
3. Use Sync after returning to the project. The button requests a real local collection and refreshes after the build id changes.
4. If another application owns the configured port, stop that application or start Skill Tracker with another `-Port` value.

Unknown tools can still be added explicitly under `custom_tools` in `config.json`; their configured log source is treated as user-authorized input.

## Validation

The following focused tests cover this release:

- `scripts/test-collector-tool-lifecycle.ps1`: removed, installed, and removed Trae transitions.
- `scripts/test-collector-codex-latest-read.ps1`: new Codex record format and latest timestamp.
- `scripts/test-collector-cache.ps1`: cross-process cache reuse and changed-file reparsing.
- `scripts/test-start-dashboard-sync.ps1`: real background watcher and HTTP sync request.
- Existing collector, watcher, launcher, port-conflict, shortcut, package, portable-release, and JavaScript regression tests.

The real local collection produced a current report on 2026-08-05 at `10:00:47` local time. Its latest detected Codex record was dated `2026-08-05T01:29:10Z`; the removed Trae source reported `installed=false`, `detected=false`, and `files_scanned=0`. That run reused 658 cached files and parsed 1 changed file.

## Known boundaries

- Automatic installation detection covers the supported desktop tools and their common Windows paths. A portable installation in a nonstandard location should be added as a configured custom source or exposed through PATH.
- The watcher checks for changes every five seconds. Manual Sync queues work immediately, but collection itself is still local background work.
- This release validates local PowerShell and browser-serving behavior. It does not claim cloud deployment or physical-device verification.
