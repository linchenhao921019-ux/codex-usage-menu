#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${CODEX_USAGE_APP_NAME:-Codex 用量}"
BUILD_PATH="${CODEX_USAGE_BUILD_PATH:-/tmp/codex-usage-menu-build}"
APP_BUILD_DIR="${CODEX_USAGE_APP_BUILD_DIR:-$ROOT_DIR/.build/app}"
APP_PATH="$APP_BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/iOSCompanion/App/Assets.xcassets/AppIcon.appiconset/Icon-1024.png"
ICONSET_DIR="$APP_BUILD_DIR/AppIcon.iconset"

cd "$ROOT_DIR"
swift build -c release --build-path "$BUILD_PATH" >&2
BINARY="$(swift build -c release --build-path "$BUILD_PATH" --show-bin-path)/codex-usage-menu"

rm -rf "$APP_PATH" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

cp "$BINARY" "$MACOS_DIR/codex-usage-menu"
chmod +x "$MACOS_DIR/codex-usage-menu"

if [[ -f "$ICON_SOURCE" ]] && command -v sips >/dev/null && command -v iconutil >/dev/null; then
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
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>Codex 用量</string>
  <key>CFBundleExecutable</key>
  <string>codex-usage-menu</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.linchenhao.codexusage.menu</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Codex 用量</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Lin Chenhao</string>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
codesign --force --deep --sign - "$APP_PATH" >/dev/null
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
xattr -dr com.apple.provenance "$APP_PATH" 2>/dev/null || true

echo "$APP_PATH"
