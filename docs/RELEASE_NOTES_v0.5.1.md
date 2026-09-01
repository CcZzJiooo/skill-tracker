# Skill Tracker v0.5.1

Released: 2026-09-01

v0.5.1 is a reliability release for local collection. It closes the gap between a live Codex conversation and the generated audit stream, and makes the two Antigravity products independently observable.

## Highlights

- Replaced the old whole-line/10 MiB skip behavior with bounded streaming JSONL reads. A very large Codex record can now be scanned without allocating the entire line, and a real `Read` of a local `SKILL.md` remains discoverable even when it occurs beyond the old safety boundary.
- Added persistent per-file cache read status and transient-read retry behavior. A locked, deleted, or otherwise unreadable log is no longer recorded as a successful empty scan; the watcher keeps the prior good cache and retries the file on a later cycle.
- Added watcher heartbeat data and a local `/api/watcher-status` endpoint. The launcher now distinguishes a live watcher from a stale PID file or an unrelated process and exposes the last scan, last successful scan, and recent error state.
- Made `output_dir` and relative `skills_roots`/`custom_tools` paths resolve from `config.json`. The dashboard launcher, collector, server, sync trigger, cache, heartbeat, and generated files now use the same configured directory.
- Split `Antigravity` and `AntigravityIDE` into separate source identities, install markers, transcript roots, tool filters, report rows, and dashboard colors:
  - `Antigravity` → `~/.gemini/antigravity/brain/`
  - `AntigravityIDE` → `~/.gemini/antigravity-ide/brain/`
- Added regression coverage for the two Antigravity layouts, a Codex log larger than 10 MiB with a late `SKILL.md` read, cache preservation during a transient lock, watcher retry after lock release, and configured dashboard output.

## Verification coverage

- The version contract now aligns `VERSION`, the CLI, the MCP server, and `CITATION.cff` at `0.5.1`.
- The Windows test suite covers collection, watcher singleton/retry behavior, dashboard startup/sync/stale-watcher handling, package contents, and source/report schemas.
- The portable package remains local-first: generated telemetry, cache, PID, and heartbeat files are excluded from the release ZIP.

The release artifact still requires a green multi-OS workflow before publication. Local Windows tests do not by themselves prove Linux/macOS device acceptance or a user's external tool installation state.
