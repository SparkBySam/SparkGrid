#!/bin/bash
# KPI answer check. Run at the end of a phase, before a merge, and before a
# commit that stages a path under Packages/SparkGridCore/Sources other than
# Rendering, under corpus, or scripts/check-kpi.sh.
# Release CLI from the repo root, so it reads corpus/known-differences.md.
# Not the debug swift test.
# Hosted CI (CI or SPARK_GRID_CI) skips. Exit 10 is a skip, not a pass.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$root/corpus/manifest.json"

if [[ -n "${CI:-}" || -n "${SPARK_GRID_CI:-}" ]]; then
  echo "private corpus is not used on hosted CI"
  exit 10
fi

if [[ ! -f "$manifest" ]]; then
  echo "check-kpi: corpus manifest is missing" >&2
  exit 1
fi

file_count="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["files"]))' "$manifest")"
if [[ "$file_count" -eq 0 ]]; then
  echo "check-kpi: corpus manifest lists no files" >&2
  exit 1
fi

# Directory that contains every file named in corpus/manifest.json.
# Prints nothing when this machine does not have the private corpus.
find_corpus_dir() {
  local manifest_path="$1"
  local name dir ok
  local -a names
  [[ -f "$manifest_path" ]] || return 0
  names=()
  while IFS= read -r name; do
    [[ -n "$name" ]] && names+=("$name")
  done < <(python3 -c 'import json,sys; print("\n".join(i["name"] for i in json.load(open(sys.argv[1]))["files"]))' "$manifest_path")
  [[ ${#names[@]} -gt 0 ]] || return 0
  for dir in "$HOME/Downloads" "$HOME/SparkGridCorpus"; do
    [[ -d "$dir" ]] || continue
    ok=1
    for name in "${names[@]}"; do
      if [[ ! -f "$dir/$name" ]]; then
        ok=0
        break
      fi
    done
    if [[ "$ok" -eq 1 ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done
}

if [[ -z "${SPARK_GRID_CORPUS:-}" ]]; then
  dir="$(find_corpus_dir "$manifest")"
  if [[ -n "$dir" ]]; then
    export SPARK_GRID_CORPUS="$dir"
  fi
fi

if [[ -z "${SPARK_GRID_CORPUS:-}" ]]; then
  echo "SPARK_GRID_CORPUS is not set"
  exit 10
fi

cd "$root"
while IFS=$'\t' read -r name sha; do
  [[ -n "$name" ]] || continue
  file="${SPARK_GRID_CORPUS}/${name}"
  if [[ ! -f "$file" ]]; then
    echo "check-kpi: missing corpus file ${name}" >&2
    exit 1
  fi
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [[ "$actual" != "$sha" ]]; then
    echo "check-kpi: checksum mismatch for ${name}" >&2
    exit 1
  fi
  swift run -c release --package-path "$root/Packages/SparkGridCore" spark-grid-cli check "$file"
done < <(python3 -c 'import json,sys; [print(i["name"]+"\t"+i["sha256"]) for i in json.load(open(sys.argv[1]))["files"]]' "$manifest")
