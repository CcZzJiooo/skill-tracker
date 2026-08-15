# Skill Tracker v0.4.0

## Purpose

This release fixes the production data path that hid real Antigravity activity
after July 31, 2026. On the current machine it restores verified Antigravity
rows for August 1, 2, and 4. August 3 has a session, but no verifiable skill
call, so it remains absent instead of being fabricated. The release also makes
the local-tool lifecycle behavior explicit: an installed tool is scanned, a
removed tool is ignored, and a newly installed tool is picked up on the next
collector refresh.

## Root cause

The installed Antigravity IDE uses this Windows layout:

`%LOCALAPPDATA%\Programs\Antigravity IDE\Antigravity IDE.exe`

The collector only recognized the legacy `Antigravity\Antigravity.exe`
layout, the `antigravity` command, and the `Antigravity` process name. The
real Antigravity brain transcripts therefore remained outside the active
source set, even though the files and daily sessions existed locally.

The second production issue was cache state. Dynamic skills such as
`user-novel-style` can come from a per-user `SKILL.md` path rather than the
global skills directory. Older cache entries did not retain that source path,
so a later refresh reused the file metadata but silently dropped the valid
historical row. That made the dashboard look current while its dates stopped
advancing.

## Fixes

- Added the current Antigravity IDE executable marker with spaces.
- Added the `antigravity-ide` command and `Antigravity IDE` process fallback.
- Preserved support for the legacy Antigravity installation layout.
- Kept installation gating: stale logs are not scanned after an IDE is
  removed.
- Added a regression test covering the exact spaced Windows path, the removed
  tool state, installation discovery, and transcript emission.
- Made the persistent collector cache version 3. Every cached hit now stores
  its `sourcePath`; cache reuse restores dynamic skills before log rows are
  emitted, so a cross-day refresh cannot lose a valid skill just because the
  skill is outside the global directory.
- Moved the watcher singleton lock ahead of skill metadata scanning. A second
  shortcut launch exits quickly instead of starting another expensive scan.
- Kept Sync asynchronous: the dashboard requests a watcher refresh and reads
  the generated files after the background collection completes.
- Kept Antigravity's brain transcript source as the call-log source. The large
  IDE application log tree is not scanned because it is not the skill-call
  source and would reintroduce the startup cost this project is designed to
  avoid.

## Verification checklist

- [x] Antigravity exists on the current machine at the spaced install path.
- [x] Antigravity sessions exist for August 1, 2, 3, and 4.
- [x] Verified August 1, 2, and 4 skill rows; verified August 3 has no
      qualifying skill call.
- [x] Removed-tool false-positive behavior remains covered by lifecycle tests.
- [x] Current spaced-path regression test passes.
- [x] Persistent-cache regression passes, including a second run that reuses
      the cache without losing a dynamically sourced skill.
- [x] Full local regression suite passes: 20/20 `test-*` scripts.
- [x] Real-machine collector verification passes with 507 raw rows and 328
      deduplicated rows; the latest generated date is August 5, 2026.
- [ ] User restarts the desktop shortcut once after updating the files.
- [ ] User confirms the dashboard shows August 1, 2, 4, and 5 rows plus the
      Antigravity tool badge; August 3 is shown only when a real skill call
      exists.

## Operational note

The first refresh after this release parses Antigravity transcript files that
were previously excluded. Later refreshes reuse the persistent file cache and
only parse changed files. The dashboard's Sync action remains asynchronous: it
accepts a refresh request and the watcher publishes the new generated files.
