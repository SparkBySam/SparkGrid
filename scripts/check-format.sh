#!/bin/bash
# swift-format lint. Non-zero lint status fails the stage. Does not rewrite files.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

if ! xcrun --find swift-format >/dev/null 2>&1; then
  echo "format: xcrun swift-format is not available" >&2
  exit 1
fi

list="$(mktemp "${TMPDIR:-/tmp}/spark-grid-format-files.XXXXXX")"
trap 'rm -f "$list"' EXIT

find \
  "$root/Packages/SparkGridCore" \
  "$root/Spark Grid" \
  "$root/Spark Grid Quick Look" \
  \( -path '*/.build/*' -o -path '*/.build' -o -path '*/.swiftpm/*' \) -prune \
  -o -name '*.swift' -print0 >"$list"

if [[ ! -s "$list" ]]; then
  echo "format: no Swift files found" >&2
  exit 1
fi

xargs -0 xcrun swift-format lint -s -p <"$list"
