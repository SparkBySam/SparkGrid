#!/bin/bash
# Fuzz smoke. A long soak sets SPARK_GRID_FUZZ_STEPS. The default is short.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$root/Packages/SparkGridCore/Package.swift"

if ! grep -q 'name: "CommandFuzz"' "$manifest"; then
  echo "check-fuzz: CommandFuzz is not built (W5). The fuzz smoke run cannot start." >&2
  exit 1
fi

export SPARK_GRID_FUZZ_SEED="${SPARK_GRID_FUZZ_SEED:-1}"
export SPARK_GRID_FUZZ_STEPS="${SPARK_GRID_FUZZ_STEPS:-20}"

cd "$root/Packages/SparkGridCore"
swift test --filter CommandFuzzTests
