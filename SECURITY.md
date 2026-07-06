# Security Policy

Skill Tracker reads local AI-agent session logs and writes local dashboard data. This means privacy and data handling are part of the security model.

## Supported Versions

The `main` branch is the active development line.

## Reporting a Vulnerability

Please open a GitHub issue if the report does not contain private data. For sensitive reports, avoid posting raw logs, session IDs, local paths, private skill names, or full internal skill descriptions.

When reporting, include:

- A short description of the risk.
- Steps to reproduce.
- Whether private local data can be exposed.
- The affected file or feature.
- A sanitized sample if needed.

## Private Data Rules

Do not paste raw generated telemetry into public issues unless you have reviewed it.

Prefer the anonymous export when sharing:

- Session summaries.
- Skill usage samples.
- Screenshots.
- Governance findings.

## Scope

In scope:

- Local telemetry leakage.
- Generated file privacy issues.
- Dashboard export issues.
- Unsafe duplicate cleanup behavior.
- GitHub radar behavior that exposes unexpected data.

Out of scope:

- Vulnerabilities in GitHub, Codex, Claude Code, Cursor, Windsurf, Antigravity, Continue, Gemini CLI, or other upstream products.
