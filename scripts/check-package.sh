#!/bin/bash
# Package build and tests. CI uses release. The pre-commit hook uses debug.
set -euo pipefail

mode="${1:-release}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/Packages/SparkGridCore"

case "$mode" in
  release)
    swift build -c release
    swift test
    ;;
  debug)
    swift build
    swift test
    ;;
  *)
    echo "check-package: mode must be release or debug" >&2
    exit 2
    ;;
esac
