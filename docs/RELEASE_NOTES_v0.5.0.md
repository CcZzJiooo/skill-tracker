# Skill Tracker v0.5.0

Released: 2026-08-16

v0.5.0 makes the local collector and dashboard launcher portable across Windows, Linux, and macOS while preserving the existing Windows one-click flow.

## Highlights

- Added `run.sh` as the Linux/macOS launcher. It resolves the project directory independently of the caller's current directory and forwards all dashboard options to PowerShell 7.
- Added native Linux XDG and macOS Application Support path discovery for editor storage, alongside the existing Windows AppData discovery.
- Replaced Windows-only watcher inspection and process launching with platform-aware implementations.
- Added `open`/`xdg-open` browser launching and native static-file path handling on Unix systems.
- Kept Desktop shortcuts and login startup Windows-only; unsupported controls are now hidden instead of reporting false success.
- Changed the release artifact to `skill-tracker-v0.5.0-portable.zip`, containing both `run.bat` and `run.sh`.
- Added a single `VERSION` source used by the CLI and MCP server, and aligned `CITATION.cff` with 0.5.0.

## Runtime requirements

| Platform | Launcher | Requirement |
|---|---|---|
| Windows | `run.bat` | Windows PowerShell 5.1 or PowerShell 7 |
| Linux | `bash run.sh` | Bash and PowerShell 7 (`pwsh`) |
| macOS | `bash run.sh` | Bash and PowerShell 7 (`pwsh`) |

Normal dashboard use does not require Node.js or Python. Node.js is only used by the optional CLI/MCP integrations and their tests.

## Verification coverage

- The GitHub Actions workflow now defines Windows, Ubuntu, and macOS runtime jobs for platform path contracts, first-run collection, local HTTP startup, version alignment, and the Unix launcher.
- The local Windows checkout validates both Windows PowerShell and PowerShell 7 behavior, package contents, checksum verification, collector output, and dashboard startup.

The multi-OS workflow must still pass on the published commit before attaching the 0.5.0 release artifact. A green local Windows run alone is not evidence of physical Linux or macOS device acceptance.
