# Skill Tracker v0.6.0

Released: 2026-09-01

v0.6.0 makes tool detection adaptive. It scans for current installation evidence before a launch and during watcher refreshes, so the dashboard reflects the tools that are actually available on the machine instead of a static list of possible products.

## Highlights

- Added a launch-time rescan. Reopening the launcher now asks an existing watcher to refresh tool installation evidence and the latest log state before the dashboard is shown.
- Added the **工具雷达 / Adaptive tools** dashboard view with current tools, known profiles, newly detected tools, removed tools, bounded unadapted candidates, install evidence, and provider hints.
- Removed the old false-positive path where a stale log directory could keep a deleted tool visible. Current UI rows come from `visible_sources`; the full `sources` array remains available as diagnostic evidence.
- Added canonical source identities for `OpenCode` and **DeepSeek Harness (`dsh`)**. `Hermes` stays a separate tool profile and is not treated as a DeepSeek Harness alias.
- Added native DeepSeek Harness JSONL parsing for `user/message`, direct `data.content` text blocks, and numeric epoch-millisecond `time` values. The collector also recognizes the official npx package cache and common global command/package locations as installation evidence.
- Added bounded upgrade candidates for Kiro, OpenClaw, Pi Agent, and OpenHands. Candidate probing checks only a small set of known paths, commands, and process names; it does not crawl the whole disk.
- Added a privacy-safe `tool-discovery` CLI command. `health` now includes the same redacted discovery summary, without local paths or raw session data.
- Added regression coverage for canonical naming, stale-log removal, npx package discovery, native DeepSeek Harness events, launch-time candidate discovery, dashboard JavaScript/markup, and CLI redaction.

## Report contract

`dashboard/tool_report.json` now exposes:

- `summary.installed_tools`: the current tool set used by the dashboard;
- `summary.known_tools`: the built-in profile catalog;
- `discovery.installed_tools`, `newly_detected_tools`, and `removed_tools`: the current scan and transition state;
- `discovery.unknown_candidates`: bounded install signals for tools without a stable adapter;
- `visible_sources`: source rows eligible for the current UI;
- `sources`: full source diagnostics, including hidden/missing paths.

The `tool-discovery` CLI intentionally omits source paths, session IDs, raw logs, and skill names. Use the local JSON report or the dashboard when path-level troubleshooting is necessary.

## Verification coverage

- The version contract aligns `VERSION`, the CLI, the MCP server, and `CITATION.cff` at `0.6.0`.
- The Windows suite covers collector discovery, official DeepSeek Harness event parsing, npx package markers, watcher transitions, launch-time rescans, dashboard radar contracts, CLI output, packaging, and stale-server handling.
- The portable package excludes generated telemetry, cache, PID, and heartbeat files as before.

Local tests prove the collector and launcher behavior in the current Windows environment. They do not by themselves prove that a user's OpenCode or DeepSeek Harness installation exists, that an external package registry is reachable, or that a release asset has been published on GitHub Releases.
