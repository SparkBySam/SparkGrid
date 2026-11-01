#!/bin/bash
# Fail if a package target below Rendering imports UI frameworks or names UI types.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/Packages/SparkGridCore/Sources"
manifest="$root/Packages/SparkGridCore/Package.swift"

if [[ ! -d "$src" ]]; then
  echo "check-layers: missing $src" >&2
  exit 1
fi

failed=0
lower=(GridCore NumberFormat Formula Functions Model Calc FileFormats Engine)

for target in "${lower[@]}"; do
  dir="$src/$target"
  if [[ ! -d "$dir" ]]; then
    echo "check-layers: missing target $target" >&2
    failed=1
    continue
  fi
  if grep -RInE --include='*.swift' 'import[[:space:]]+(AppKit|SwiftUI|Cocoa|UIKit)\b' "$dir"; then
    echo "check-layers: $target imports a UI framework" >&2
    failed=1
  fi
  if grep -RInE --include='*.swift' '\b(NSView|NSColor|NSFont)\b' "$dir"; then
    echo "check-layers: $target references NSView, NSColor, or NSFont" >&2
    failed=1
  fi
done

python3 - "$manifest" << 'PY' || failed=1
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
order = ["GridCore", "NumberFormat", "Formula", "Functions", "Model", "Calc", "FileFormats", "Engine", "Rendering", "SparkGridCore"]
rank = {name: index for index, name in enumerate(order)}
# Target blocks start with .target( or .testTarget(
parts = re.split(r'\.(?:target|testTarget)\(', text)
for part in parts[1:]:
    name_match = re.search(r'name:\s*"([^"]+)"', part)
    if not name_match:
        continue
    name = name_match.group(1)
    if name not in rank:
        continue
    deps = re.findall(r'"(GridCore|NumberFormat|Formula|Functions|Model|Calc|FileFormats|Engine|Rendering|SparkGridCore)"', part)
    # The name itself appears in name: "...". Drop the first match of the target name.
    seen_self = False
    for dep in deps:
        if dep == name and not seen_self:
            seen_self = True
            continue
        if dep not in rank:
            continue
        if rank[dep] >= rank[name]:
            print(f"check-layers: {name} depends on {dep}, which is not a lower layer", file=sys.stderr)
            sys.exit(1)
sys.exit(0)
PY

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "check-layers: pass"
