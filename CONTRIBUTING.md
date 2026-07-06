# Contributing to Skill Tracker

Thanks for considering a contribution. Skill Tracker is early-stage, so high-signal issues, screenshots, adapters, and documentation fixes are all useful.

## Good First Contributions

- Add a new AI tool log adapter.
- Improve skill-category rules in `collect.ps1`.
- Improve Chinese or English copy in the dashboard manual.
- Add validation for exported `skill_catalog.json`.
- Improve privacy handling for anonymous exports.
- Add reproducible screenshots or demo datasets.

## Development Flow

1. Fork the repository.
2. Create a focused branch.
3. Keep local telemetry files out of Git.
4. Test with demo data and, if possible, with real local logs.
5. Open a pull request using the PR template.

## Local Files That Should Stay Private

Do not commit generated telemetry:

- `dashboard/skill_data.js`
- `dashboard/skill_log.js`
- `dashboard/skill_call_stats.json`
- `dashboard/skill_catalog.json`
- `dashboard/skill_catalog.js`
- `.playwright-mcp/`
- `.agents/`
- `.codex/`

## Pull Request Standard

A good PR should explain:

- What changed.
- Why the change is useful.
- How it was tested.
- Whether it changes privacy behavior.
- Screenshots, if the dashboard UI changed.

## Language

English is preferred for public issue titles and PR titles because it improves search and discovery. Chinese is welcome in issue bodies, screenshots, explanations, and translations.
