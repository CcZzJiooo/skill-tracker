#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v pwsh >/dev/null 2>&1; then
  printf '%s\n' \
    'PowerShell 7 (pwsh) is required to collect local Skill Tracker data.' \
    'Install it from https://learn.microsoft.com/powershell/scripting/install/installing-powershell, then run this launcher again.' >&2
  exit 127
fi

exec pwsh -NoLogo -NoProfile -File "$script_dir/start-dashboard.ps1" "$@"
