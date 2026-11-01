#!/bin/bash
# Tracked paths only. Dependency checkouts under .build are not in git.
# Exit 1 on customer-shaped files. Do not print file contents.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

allow_file="$root/scripts/privacy-allowlist.txt"
declare -a allow=()
if [[ -f "$allow_file" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    allow+=("$line")
  done <"$allow_file"
fi

is_allowed() {
  local path="$1"
  local item
  if [[ "${#allow[@]}" -eq 0 ]]; then
    return 1
  fi
  for item in "${allow[@]}"; do
    if [[ "$item" == "$path" ]]; then
      return 0
    fi
  done
  return 1
}

failed=0

while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  case "$path" in
    Fixtures/*|fixtures/*) continue ;;
  esac
  lower="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.xlsx|*.xls|*.csv|*.ods)
      echo "check-privacy: tracked spreadsheet outside Fixtures/: $path" >&2
      failed=1
      ;;
  esac
done < <(git ls-files)

while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if [[ "$path" == "scripts/answers/ledger-answers.txt" ]]; then
    continue
  fi
  echo "check-privacy: $path is under scripts/answers/ and is not the synthetic ledger answers" >&2
  failed=1
done < <(git ls-files 'scripts/answers')

while IFS= read -r -d '' path; do
  [[ -z "$path" || ! -f "$path" ]] && continue
  if is_allowed "$path"; then
    continue
  fi
  bytes="$(wc -c <"$path" | tr -d '[:space:]')"
  if [[ "$bytes" -gt 1048576 ]]; then
    echo "check-privacy: tracked file over 1 MB and not on scripts/privacy-allowlist.txt: $path" >&2
    failed=1
  fi
done < <(git ls-files -z)

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "check-privacy: pass"
