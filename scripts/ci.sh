#!/bin/bash
# Commit gate. Stages run in order and stop at the first failure.
# Exit 10 from a stage is a documented skip, not a weakened check.
# A local KPI skip is a failure. Hosted CI may still skip that stage.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
ci_app_dd="/tmp/spark-grid-ci-app"
ci_ql_dd="/tmp/spark-grid-ci-ql"
cleanup_ci_builds() {
  rm -rf "$ci_app_dd" "$ci_ql_dd"
}
trap cleanup_ci_builds EXIT
started="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"
elapsed() {
  perl -MTime::HiRes=time -e 'printf "%.1f", time - $ARGV[0]' "$started"
}

hosted_ci() {
  [[ -n "${CI:-}" || -n "${SPARK_GRID_CI:-}" ]]
}

run_stage() {
  local name="$1"
  shift
  local log code reason
  log="$(mktemp "${TMPDIR:-/tmp}/spark-grid-ci.XXXXXX")"
  set +e
  "$@" >"$log" 2>&1
  code=$?
  set -e
  if [[ "$code" -eq 0 ]]; then
    echo "$name: PASS"
  elif [[ "$code" -eq 10 ]]; then
    if [[ "$name" == "kpi" ]] && ! hosted_ci; then
      cat "$log" >&2
      echo "$name: FAIL"
      echo "FAIL ($(elapsed)s)"
      rm -f "$log"
      exit 1
    fi
    reason="$(tr '\n' ' ' <"$log" | sed 's/[[:space:]]*$//')"
    echo "$name: SKIP ${reason}"
  else
    cat "$log" >&2
    echo "$name: FAIL"
    echo "FAIL ($(elapsed)s)"
    rm -f "$log"
    exit 1
  fi
  rm -f "$log"
}

privacy_and_assets() {
  set +e
  "$root/scripts/check-privacy.sh"
  local privacy=$?
  "$root/scripts/check-assets.sh"
  local assets=$?
  set -e
  [[ "$privacy" -eq 0 && "$assets" -eq 0 ]]
}

# End of a phase and before a merge. The pre-commit hook runs this when a
# staged path is under Packages/SparkGridCore/Sources other than Rendering,
# under corpus, or is scripts/check-kpi.sh.
kpi_stage() {
  "$root/scripts/check-kpi.sh"
}

run_stage lint "$root/scripts/lint.sh"
run_stage format "$root/scripts/check-format.sh"
run_stage package "$root/scripts/check-package.sh" release
run_stage xcodebuild "$root/scripts/check-xcodebuild.sh"
run_stage layers "$root/scripts/check-layers.sh"
run_stage privacy-assets privacy_and_assets
run_stage ledger "$root/scripts/check-ledger.sh"
run_stage kpi kpi_stage
run_stage fuzz "$root/scripts/check-fuzz.sh"

echo "PASS ($(elapsed)s)"
