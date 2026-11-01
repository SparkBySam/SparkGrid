#!/bin/bash
# Ledger ground truth. Python computes the expected formula results.
# The workbook and the answer file stay in /tmp.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$root/Packages/SparkGridCore/Package.swift"

if ! grep -q 'name: "AnswerCheck"' "$manifest"; then
  echo "check-ledger: AnswerCheck is not built (W5). The ledger saved-result check cannot run." >&2
  exit 1
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/spark-grid-ledger.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
python3 "$root/scripts/generate_ledger_workbook.py" -o "$tmp/ledger.xlsx" --answers "$tmp/answers.txt"

export SPARK_GRID_LEDGER_CHECK=1
export SPARK_GRID_LEDGER_XLSX="$tmp/ledger.xlsx"
export SPARK_GRID_LEDGER_ANSWERS="$tmp/answers.txt"

cd "$root/Packages/SparkGridCore"
swift test --filter LedgerAnswerCheck
