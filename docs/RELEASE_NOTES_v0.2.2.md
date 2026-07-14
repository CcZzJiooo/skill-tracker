# Skill Tracker v0.2.2

## Automatic Chinese Skill Summaries

This release fixes the catalog behavior for newly installed skills. A skill with an English-only `SKILL.md` no longer appears with a blank Chinese field.

- Parses `SKILL.md` frontmatter, including multiline `description`, optional Chinese description fields, and `triggers`.
- Reads a bounded body excerpt when frontmatter is incomplete.
- Generates a concise Chinese functional summary locally with a stable semantic rule set; no skill content is sent to a translation service.
- Records `zh_desc_source`, `zh_desc_input_hash`, and `translation_version` so generated and human-maintained text remain distinguishable.
- Treats legacy catalog entries with non-empty Chinese text as manual content, preventing accidental overwrites.

## Live Skill Discovery

- Watch mode now detects newly created, modified, or removed `SKILL.md` files and refreshes the catalog without requiring a restart.
- Automatic summaries are regenerated when a source skill changes or the local summarizer version changes.
- Existing watcher singleton behavior and local-first log collection remain unchanged.

## Dashboard And Export

- Catalog rows show whether a description came from automatic parsing, source-file Chinese metadata, or manual editing.
- Editing a description immediately marks it as `手工编辑`.
- Catalog export preserves the source marker and marks edited rows as `manual`, so the next collection cannot replace them.
- Existing GitHub radar description normalization and false-positive skill filtering remain covered by regression tests.

### Post-release dashboard polish

- The header keeps the first four detected tools visible and places the remainder behind an expandable count, preventing a long tool list from crowding primary actions.
- Overview statistics now show their real local data span and support an inclusive start/end date filter. The filter updates overview cards, rankings, skill details, and audit rows together.
- Mobile navigation is condensed into a two-column task grid so the dashboard content appears in the first scroll length instead of after a full-height sidebar.
- Launcher regression fixtures now provide their own known `SKILL.md` and isolated user-data paths, preserving the collector's false-positive defense while keeping release checks machine-independent.

## Documentation And Release Files

- Updated README release commands and portable ZIP names to `v0.2.2`.
- Updated `CITATION.cff` to version `0.2.2` with the release date.
- Added this release note and linked the previous release as superseded.

## Validation

- Automatic translation fixture: passed.
- Watcher discovers a skill installed after startup: passed.
- First-run, empty-run, false-positive, watcher singleton, and collector verification checks: passed.
- GitHub result formatting regression: passed.
- Dashboard validation in Edge + Playwright at desktop and mobile sizes: passed with no page or console errors.
- Date-range interactions, header tool overflow, and the revised mobile layout: passed in local rendered checks with no console errors.

## Download And Run

1. Download `skill-tracker-v0.2.2-windows-portable.zip` and `SHA256SUMS.txt` from GitHub Releases.
2. Optionally verify the ZIP hash against `SHA256SUMS.txt`.
3. Unzip the package and double-click `run.bat`.

The portable package remains local-first and does not include generated private telemetry files.
