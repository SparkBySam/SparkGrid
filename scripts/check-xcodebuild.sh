#!/bin/bash
# Release builds of the app and Quick Look into separate /tmp derived-data folders.
# Exit 10 when hosted CI does not have Xcode 27. That skip does not change
# the deployment target or the Swift language mode.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app_dd="/tmp/spark-grid-ci-app"
ql_dd="/tmp/spark-grid-ci-ql"

cleanup() {
  rm -rf "$app_dd" "$ql_dd"
}
trap cleanup EXIT

if [[ -n "${CI:-}" ]]; then
  line="$(xcodebuild -version | awk 'NR==1 {print $2}')"
  major="${line%%.*}"
  if [[ -z "$major" || ! "$major" =~ ^[0-9]+$ ]]; then
    echo "xcodebuild: could not read the Xcode version" >&2
    exit 1
  fi
  if [[ "$major" -lt 27 ]]; then
    echo "Xcode ${line} is older than 27. Deployment target stays macOS 14.0. Swift stays 5.0."
    exit 10
  fi
fi

xcodebuild \
  -project "$root/Spark Grid.xcodeproj" \
  -scheme "Spark Grid" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$app_dd" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project "$root/Spark Grid.xcodeproj" \
  -scheme "Spark Grid Quick Look" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$ql_dd" \
  CODE_SIGNING_ALLOWED=NO \
  build
