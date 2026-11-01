#!/bin/bash
# Every bundled app asset needs a row in ATTRIBUTION.md. W8 writes that file.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
attr="$root/ATTRIBUTION.md"
failed=0

assets="$(git ls-files "Spark Grid" "Spark Grid Quick Look" | awk 'BEGIN { IGNORECASE = 1 } /\.(png|jpg|jpeg|gif|pdf|svg|heic|icns|ttf|otf)$/')"

if [[ ! -f "$attr" ]]; then
  echo "check-assets: ATTRIBUTION.md is missing. Each bundled asset needs author, source, and license." >&2
  if [[ -n "$assets" ]]; then
    printf '%s\n' "$assets" | sed 's/^/check-assets: missing row for /' >&2
  fi
  exit 1
fi

if [[ -z "$assets" ]]; then
  echo "check-assets: pass (no bundled image, font, or pdf files)"
  exit 0
fi

while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if ! grep -F -q -- "$path" "$attr"; then
    echo "check-assets: no ATTRIBUTION.md row for $path" >&2
    failed=1
  fi
done <<<"$assets"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "check-assets: pass"
