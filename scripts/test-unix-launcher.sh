#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temp_root="$(mktemp -d)"
trap 'rm -rf "$temp_root"' EXIT

mkdir -p "$temp_root/bin" "$temp_root/elsewhere"
capture_file="$temp_root/args.txt"

cat > "$temp_root/bin/pwsh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$SKILL_TRACKER_TEST_ARGS"
MOCK
chmod +x "$temp_root/bin/pwsh"

(
  cd "$temp_root/elsewhere"
  SKILL_TRACKER_TEST_ARGS="$capture_file" PATH="$temp_root/bin:$PATH" \
    bash "$repo_root/run.sh" -NoBrowser -NoWatch -Port 19001
)

mapfile -t actual < "$capture_file"
expected=(
  "-NoLogo"
  "-NoProfile"
  "-File"
  "$repo_root/start-dashboard.ps1"
  "-NoBrowser"
  "-NoWatch"
  "-Port"
  "19001"
)

if [[ "${#actual[@]}" -ne "${#expected[@]}" ]]; then
  printf 'Expected %s arguments, got %s\n' "${#expected[@]}" "${#actual[@]}" >&2
  exit 1
fi

for index in "${!expected[@]}"; do
  if [[ "${actual[$index]}" != "${expected[$index]}" ]]; then
    printf 'Argument %s mismatch: expected %q, got %q\n' \
      "$index" "${expected[$index]}" "${actual[$index]}" >&2
    exit 1
  fi
done

printf 'Unix launcher contract passed.\n'
