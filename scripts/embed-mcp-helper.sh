#!/bin/sh
# Xcode build phase: compiles spark-grid-mcp into Spark Grid.app/Contents/Helpers and signs it
# with its own sandbox entitlements (an assistant starts it, not the app, so it cannot inherit
# the app's sandbox). Foundation only; one file, so swiftc builds it without SwiftPM.
set -eu
src="$SRCROOT/Packages/SparkGridCore/Sources/spark-grid-mcp/main.swift"
plist="$SRCROOT/MCP Helper/Info.plist"
entitlements="$SRCROOT/MCP Helper/spark-grid-mcp.entitlements"
helpers="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
out="$helpers/spark-grid-mcp"
work="$DERIVED_FILE_DIR/spark-grid-mcp"
mkdir -p "$helpers" "$work"

# The helper drives, and may send Apple Events only to, the app it ships in.
app_plist="$work/Info.plist"
sed "s/>com\.sparkbysam\.SparkGrid</>$PRODUCT_BUNDLE_IDENTIFIER</" "$plist" >"$app_plist"

optimize="-Onone"
[ "$CONFIGURATION" = "Release" ] && optimize="-O"
slices=""
for arch in $ARCHS; do
  xcrun -sdk "$SDKROOT" swiftc "$optimize" -swift-version 5 \
    -target "$arch-apple-macos$MACOSX_DEPLOYMENT_TARGET" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$app_plist" \
    -o "$work/spark-grid-mcp-$arch" "$src"
  slices="$slices|$work/spark-grid-mcp-$arch"
done
# Each slice path once (paths may hold spaces; the build folder declares them as outputs).
old_ifs=$IFS
IFS='|'
# shellcheck disable=SC2086
set -- ${slices#|}
IFS=$old_ifs
xcrun lipo -create "$@" -output "$out"

signed_entitlements="$work/spark-grid-mcp.entitlements"
sed "s/>com\.sparkbysam\.SparkGrid</>$PRODUCT_BUNDLE_IDENTIFIER</" "$entitlements" >"$signed_entitlements"

identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
[ -z "$identity" ] && identity="-"
runtime=""
[ "${ENABLE_HARDENED_RUNTIME:-NO}" = "YES" ] && runtime="--options runtime"
# shellcheck disable=SC2086
codesign --force --sign "$identity" $runtime --timestamp=none \
  --identifier com.sparkbysam.SparkGrid.mcp --entitlements "$signed_entitlements" "$out"
