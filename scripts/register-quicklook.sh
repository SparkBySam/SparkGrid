#!/bin/bash
# Register Spark Grid's Finder Quick Look extension and refresh generators.
# Finds /Applications, a local .app next to the repo, or the newest DerivedData build
# that already embeds Spark Grid Quick Look.appex.
set -euo pipefail

BUNDLE_ID="com.sparkbysam.SparkGrid.QuickLook"
APP_NAME="Spark Grid"
APPEX_NAME="Spark Grid Quick Look.appex"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

appex_path_in_app() {
  local app="$1"
  echo "${app}/Contents/PlugIns/${APPEX_NAME}"
}

app_has_appex() {
  local app="$1"
  [[ -d "$(appex_path_in_app "$app")" ]]
}

resolve_app() {
  # 1) Explicit path
  if [[ -n "${1:-}" ]]; then
    if [[ -d "$1" ]] && app_has_appex "$1"; then
      echo "$1"
      return 0
    fi
    if [[ -d "$1" ]]; then
      echo "error: found app at $1 but Quick Look appex is missing:" >&2
      echo "  $(appex_path_in_app "$1")" >&2
      echo "Build the Spark Grid scheme in Xcode (Product → Run) so the extension is embedded, then re-run." >&2
      return 2
    fi
    echo "error: not an app bundle: $1" >&2
    return 1
  fi

  # 2) /Applications
  if [[ -d "/Applications/${APP_NAME}.app" ]] && app_has_appex "/Applications/${APP_NAME}.app"; then
    echo "/Applications/${APP_NAME}.app"
    return 0
  fi

  # 3) Repo-adjacent build products
  local candidate
  for candidate in \
    "${REPO_ROOT}/build/Build/Products/Debug/${APP_NAME}.app" \
    "${REPO_ROOT}/build/Build/Products/Release/${APP_NAME}.app" \
    "${REPO_ROOT}/DerivedData/Build/Products/Debug/${APP_NAME}.app" \
    "${REPO_ROOT}/DerivedData/Build/Products/Release/${APP_NAME}.app"
  do
    if [[ -d "$candidate" ]] && app_has_appex "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done

  # 4) Newest Xcode DerivedData build that embeds the appex
  local derived="${HOME}/Library/Developer/Xcode/DerivedData"
  if [[ -d "$derived" ]]; then
    # Prefer paths that contain both Spark Grid.app and the Quick Look appex.
    candidate="$(
      find "$derived" -type d -name "${APP_NAME}.app" 2>/dev/null \
        | while read -r app; do
            if app_has_appex "$app"; then
              echo "$(stat -f '%m %N' "$app" 2>/dev/null || stat -c '%Y %n' "$app" 2>/dev/null || echo "0 $app")"
            fi
          done \
        | sort -nr \
        | head -n 1 \
        | sed 's/^[0-9[:space:]]*//'
    )"
    if [[ -n "${candidate}" && -d "${candidate}" ]]; then
      echo "$candidate"
      return 0
    fi
  fi

  # 5) Launch Services match (only if appex present)
  local ls_path
  ls_path="$(mdfind "kMDItemCFBundleIdentifier == 'com.sparkbysam.SparkGrid'" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$ls_path" && -d "$ls_path" ]] && app_has_appex "$ls_path"; then
    echo "$ls_path"
    return 0
  fi

  return 1
}

print_build_help() {
  cat >&2 <<EOF
error: couldn't find a ${APP_NAME}.app that embeds ${APPEX_NAME}.

Build first, then register:

  1. Open Spark Grid.xcodeproj in Xcode
  2. Product → Run  (scheme: Spark Grid)
  3. Re-run:  ./scripts/register-quicklook.sh

Optional: point at a specific build:

  ./scripts/register-quicklook.sh "/path/to/Spark Grid.app"
EOF
}

APP_PATH="$(resolve_app "${1:-}" || true)"
status=$?
if [[ -z "${APP_PATH}" ]]; then
  # resolve_app may have already printed a specific missing-appex error (exit 2)
  if [[ "${1:-}" == "" ]]; then
    print_build_help
  fi
  exit 1
fi

APPEX="$(appex_path_in_app "$APP_PATH")"
echo "Using app:   $APP_PATH"
echo "Using appex: $APPEX"

# Launch once so LaunchServices / PlugInKit discover the appex.
open -a "$APP_PATH" || true
sleep 1

pluginkit -a "$APPEX" || true
pluginkit -e use -i "$BUNDLE_ID" || true

killall quicklookd QuickLookUIService 2>/dev/null || true
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

echo
echo "Registered extensions matching Spark Grid:"
pluginkit -mAvvv -p com.apple.quicklook.preview 2>/dev/null | grep -i -A2 -B2 "SparkGrid\|Spark Grid" || {
  echo "(no Spark Grid preview plugin listed yet — try launching the app once more)"
}

echo
echo "Done. In Finder, select a .csv or .xlsx and press Space."
echo "You should see the Spark Grid toolbar (Save / Open in Spark Grid)."
