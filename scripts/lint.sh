#!/bin/bash
# SwiftLint 0.65.1, strict, W4 crash rules. The binary is not committed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="0.65.1"
sha="c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"
url="https://github.com/realm/SwiftLint/releases/download/${version}/portable_swiftlint.zip"
tool_dir="$root/.tools/swiftlint-${version}"
bin="$tool_dir/swiftlint"

tmp=""
log=""
cleanup() {
  if [[ -n "$tmp" ]]; then
    rm -rf "$tmp"
  fi
  if [[ -n "$log" ]]; then
    rm -f "$log"
  fi
}
trap cleanup EXIT

if [[ ! -x "$bin" ]]; then
  mkdir -p "$tool_dir"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/spark-grid-swiftlint.XXXXXX")"
  curl -fsSL -o "$tmp/portable_swiftlint.zip" "$url"
  actual="$(shasum -a 256 "$tmp/portable_swiftlint.zip" | awk '{print $1}')"
  if [[ "$actual" != "$sha" ]]; then
    echo "lint: SwiftLint ${version} zip sha256 mismatch" >&2
    echo "lint: expected ${sha}" >&2
    echo "lint: actual   ${actual}" >&2
    exit 1
  fi
  unzip -q "$tmp/portable_swiftlint.zip" -d "$tmp/unzip"
  found=""
  while IFS= read -r candidate; do
    found="$candidate"
    break
  done < <(find "$tmp/unzip" -type f -name swiftlint)
  if [[ -z "$found" ]]; then
    echo "lint: portable_swiftlint.zip did not contain a swiftlint binary" >&2
    exit 1
  fi
  cp "$found" "$bin"
  chmod +x "$bin"
  rm -rf "$tmp"
  tmp=""
fi

got="$("$bin" version | head -n 1 | awk '{print $1}')"
if [[ "$got" != "$version" ]]; then
  echo "lint: swiftlint reported ${got}, expected ${version}" >&2
  exit 1
fi

cache="$root/.tools/swiftlint-cache"
mkdir -p "$cache"
log="$(mktemp "${TMPDIR:-/tmp}/spark-grid-swiftlint-log.XXXXXX")"

set +e
# Custom rules are skipped when SourceKit is disabled, so this stage does not pass --disable-sourcekit.
"$bin" lint --strict --quiet \
  --cache-path "$cache" \
  --config "$root/.swiftlint.yml" \
  --working-directory "$root" \
  >"$log" 2>&1
code=$?
set -e

count="$(grep -c . "$log" || true)"
if [[ "$code" -ne 0 ]]; then
  full="${TMPDIR:-/tmp}/spark-grid-swiftlint.txt"
  cp "$log" "$full"
  echo "lint: SwiftLint ${version} strict found ${count} violation lines. Full list: ${full}" >&2
  head -n 40 "$log" >&2 || true
  if [[ "$count" -gt 40 ]]; then
    echo "lint: $((count - 40)) more lines in ${full}" >&2
  fi
  exit "$code"
fi

echo "lint: SwiftLint ${version} strict, no violations"
exit 0
