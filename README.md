# Skill Tracker

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Local-first](https://img.shields.io/badge/local--first-yes-577d17)](#privacy-first)
[![Windows](https://img.shields.io/badge/Windows-supported-55a7ff)](#quick-start)
[![AI agents](https://img.shields.io/badge/AI%20agents-skills%20observability-b9f35a)](#why-skill-tracker)

Local-first observability for AI agent skills.

Skill Tracker scans local AI coding-agent session logs, detects `SKILL.md` usage, and turns skill calls into a private dashboard: heatmaps, timelines, Chinese skill descriptions, duplicate-skill governance, GitHub discovery, and exportable action plans.

![Skill Tracker dashboard desktop preview](docs/preview-desktop.png)

## Why Skill Tracker

Modern AI coding agents can call skills, plugins, prompts, and local workflows, but most users cannot see what was actually used, which skills overlap, or which descriptions are missing.

Skill Tracker makes that hidden layer visible.

- See which skills are used across Codex, Claude Code, Cursor, Windsurf, Antigravity, Continue, and Gemini CLI.
- Translate each skill's purpose into Chinese so non-English users can understand the local skill library.
- Search by natural language intent, such as "I need a skill that saves tokens".
- Detect duplicated or overlapping skills and export reviewable cleanup plans.
- Generate GitHub issue drafts from governance findings.
- Keep everything local by default. No server is required.

## 中文简介

Skill Tracker 是一个本地优先的 AI Agent 技能调用可视化工具。它扫描本机 AI 编程工具的会话日志，统计哪些 `SKILL.md` 被调用，并在静态 dashboard 中展示技能热度、调用链路、中文功能说明、重复 skill 治理、GitHub 搜索和可导出的行动方案。

它适合想管理 Codex / Claude Code / Cursor / Windsurf / Antigravity / Gemini CLI 等工具技能体系的开发者。

## Quick Start

Windows:

```powershell
git clone https://github.com/CcZzJiooo/skill-tracker.git
cd skill-tracker
.\run.bat
```

Manual mode:

```powershell
powershell -ExecutionPolicy Bypass -File .\collect.ps1
start .\dashboard\index.html
```

If no local logs have been collected yet, the dashboard opens with synthetic demo data from `dashboard/demo_data.js`, so contributors can inspect the interface immediately after cloning.

## Core Features

| Area | What it does |
|---|---|
| Skill call visualization | Shows total calls, deduplicated calls, active skills, top skills, recent sessions, and per-tool usage. |
| Chinese skill dictionary | Maintains Chinese descriptions for every skill and supports filtering by category, missing description, and edited state. |
| Intent search | Matches Chinese or English user intent against local skills, descriptions, triggers, and categories. |
| Governance radar | Scores skill health, finds missing metadata, duplicate reads, similar skills, and conflict risks. |
| Action lab | Turns governance findings into P0/P1/P2 tasks with evidence and acceptance criteria. |
| Duplicate cleanup export | Exports a JSON cleanup plan and a PowerShell archive script. The script previews by default and only moves files when explicitly applied. |
| Skill x tool matrix | Shows cross-platform skill coverage and tool preference patterns. |
| GitHub radar | Searches public GitHub repositories, checks repository freshness, latest release, and API rate limit state. |
| Anonymous export | Exports privacy-safe reports without real session IDs, local paths, raw skill names, or full descriptions. |
| Built-in manual | Explains every dashboard section inside the app, because many GitHub users do not read README files first. |

## Supported Sources

Skill Tracker currently detects common local paths for:

| Tool | Example log path |
|---|---|
| Antigravity IDE | `~/.gemini/antigravity-ide/brain/` |
| Claude Code | `~/.claude/projects/` |
| Codex | `~/.codex/sessions/`, `~/.codex/archived_sessions/` |
| Cursor | `%APPDATA%/Cursor/logs/` |
| Windsurf | `%APPDATA%/Windsurf/logs/` |
| Continue | `~/.continue/sessions/` |
| Gemini CLI | `~/.gemini/sessions/` |

Skill roots are auto-detected from common local skill folders. You can also set your own path in `config.json`.

## Configuration

Edit `config.json`:

```json
{
  "skills_root": "",
  "output_dir": "./dashboard",
  "max_log_entries": 5000,
  "dedup_window_minutes": 2,
  "custom_tools": [
    { "name": "MyTool", "path": "C:/Users/YOU/.mytool/sessions" }
  ]
}
```

Fields:

- `skills_root`: Local skill directory. Leave empty to auto-detect common folders.
- `output_dir`: Dashboard data output directory.
- `max_log_entries`: Maximum log entries emitted for the dashboard.
- `dedup_window_minutes`: Time bucket used to collapse repeated reads.
- `custom_tools`: Extra tool names and session-log directories.

## Generated Files

Running `collect.ps1` generates or updates:

- `dashboard/skill_data.js`
- `dashboard/skill_log.js`
- `dashboard/skill_call_stats.json`
- `dashboard/skill_catalog.json`
- `dashboard/skill_catalog.js`

These real local telemetry files are ignored by Git on purpose. They may contain private session IDs, local paths, and internal skill metadata. The public demo data is `dashboard/demo_data.js`.

## Privacy First

Skill Tracker is designed as a local-first tool.

- It reads local logs and writes local dashboard files.
- It does not upload local skill telemetry.
- GitHub search is optional and only runs from the dashboard when you use GitHub radar.
- Anonymous export removes real session IDs, local paths, raw skill names, and full skill descriptions.

Before sharing screenshots, prefer demo data or the anonymous export.

## How It Works

AI agents usually load a skill by reading a path like:

```text
skills/<name>/SKILL.md
```

Skill Tracker scans local session logs for those reads, extracts skill name, source tool, timestamp, and session identifier, then emits static JS/JSON data files for `dashboard/index.html`.

Default deduplication key:

```text
tool + session/file + skill + time bucket
```

For example, with `dedup_window_minutes = 2`, repeated reads of the same skill in the same session within two minutes count as one deduplicated call while the raw read count is preserved.

## Open Source Positioning

This project is not another generic dashboard. It focuses on a new layer of AI-agent tooling: skill observability and skill governance.

Potential use cases:

- Audit which skills an agent actually uses.
- Translate and maintain a shared skill dictionary.
- Find duplicate or overlapping skills before they become prompt debt.
- Compare skill coverage across tools.
- Prepare clean GitHub issues from governance findings.
- Publish privacy-safe skill-usage reports.

## Repository Layout

```text
skill-tracker/
|-- collect.ps1
|-- config.json
|-- run.bat
|-- dashboard/
|   |-- index.html
|   |-- demo_data.js
|   |-- skill_catalog.json      # generated, ignored
|   |-- skill_catalog.js        # generated, ignored
|   |-- skill_data.js           # generated, ignored
|   |-- skill_log.js            # generated, ignored
|   `-- skill_call_stats.json   # generated, ignored
|-- docs/
|   |-- LAUNCH_KIT.md
|   |-- ROADMAP.md
|   |-- preview-desktop.png
|   `-- preview-mobile.png
|-- .github/
|   |-- ISSUE_TEMPLATE/
|   `-- PULL_REQUEST_TEMPLATE.md
|-- NOTICE
|-- CITATION.cff
|-- CONTRIBUTING.md
|-- SECURITY.md
|-- CODE_OF_CONDUCT.md
|-- SUPPORT.md
|-- LICENSE
`-- README.md
```

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md).

Near-term priorities:

- Better cross-platform path detection.
- More skill-source adapters.
- Import validation for `skill_catalog.json`.
- A small CLI wrapper, such as `skill-tracker collect` and `skill-tracker open`.
- Optional GitHub token support for higher API limits.

## Spread the Project

If Skill Tracker helps you understand your AI-agent skill stack, the most useful support is:

- Star the repository.
- Share a screenshot with demo or anonymized data.
- Open an issue for a new tool adapter.
- Submit a pull request for better skill-category rules.
- Mention the project when discussing AI-agent observability.

Ready-to-post launch copy is in [docs/LAUNCH_KIT.md](docs/LAUNCH_KIT.md).

## Attribution

If you use this project in another repository, article, video, product, or dataset, please keep the license notice and link back to:

```text
https://github.com/CcZzJiooo/skill-tracker
```

Citation metadata is available in [CITATION.cff](CITATION.cff). Additional attribution notes are in [NOTICE](NOTICE).

## License

MIT. See [LICENSE](LICENSE).
