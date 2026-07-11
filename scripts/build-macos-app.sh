#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${CODEX_USAGE_APP_NAME:-Codex 用量}"
APP_BUILD_DIR="${CODEX_USAGE_APP_BUILD_DIR:-/tmp/codex-usage-menu-app-build}"
DERIVED_DATA="${CODEX_USAGE_XCODE_DERIVED_DATA:-/tmp/codex-usage-mac-xcodebuild}"
PROJECT_PATH="$ROOT_DIR/MacApp/CodexUsageMac.xcodeproj"
APP_PATH="$APP_BUILD_DIR/$APP_NAME.app"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
ICON_SOURCE="$ROOT_DIR/iOSCompanion/App/Assets.xcassets/AppIcon.appiconset/Icon-1024.png"
ICONSET_DIR="$APP_BUILD_DIR/AppIcon.iconset"
WIDGET_ENTITLEMENTS="$ROOT_DIR/Sources/CodexUsageMacWidget/CodexUsageMacWidget.entitlements"
SIGN_IDENTITY="${CODEX_USAGE_CODE_SIGN_IDENTITY:--}"
ARCHS="${CODEX_USAGE_ARCHS:-$(uname -m)}"

if [[ "$ARCHS" == *" "* ]]; then
  DESTINATION="generic/platform=macOS"
else
  DESTINATION="platform=macOS,arch=$ARCHS"
fi

rm -rf "$DERIVED_DATA"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme CodexUsageMenu \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "$DESTINATION" \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS="$ARCHS" \
  ONLY_ACTIVE_ARCH=NO \
  build >&2

rm -rf "$APP_PATH" "$ICONSET_DIR"
mkdir -p "$APP_BUILD_DIR"
ditto "$BUILT_APP" "$APP_PATH"

if [[ -f "$ICON_SOURCE" ]] && command -v sips >/dev/null && command -v iconutil >/dev/null; then
  mkdir -p "$ICONSET_DIR" "$APP_PATH/Contents/Resources"
  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET_DIR" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

APPEX="$APP_PATH/Contents/PlugIns/CodexUsageMacWidgetExtension.appex"
if [[ ! -d "$APPEX" ]]; then
  echo "Missing macOS widget extension: $APPEX" >&2
  exit 1
fi

xattr -cr "$APP_PATH" 2>/dev/null || true
codesign --remove-signature "$APPEX" >/dev/null 2>&1 || true
codesign --remove-signature "$APP_PATH" >/dev/null 2>&1 || true
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none --entitlements "$WIDGET_ENTITLEMENTS" "$APPEX" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP_PATH" >/dev/null
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
xattr -dr com.apple.provenance "$APP_PATH" 2>/dev/null || true

echo "$APP_PATH"
