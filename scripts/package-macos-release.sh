#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${CODEX_USAGE_APP_NAME:-Codex 用量}"
RELEASE_ARCHS="${CODEX_USAGE_RELEASE_ARCHS:-arm64 x86_64}"
ARCH_LABEL="${CODEX_USAGE_RELEASE_ARCH_LABEL:-universal}"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_NAME="CodexUsageMenu-macOS-$ARCH_LABEL"
PACKAGE_DIR="$DIST_DIR/$PACKAGE_NAME"
ZIP_PATH="$DIST_DIR/$PACKAGE_NAME.zip"

mkdir -p "$DIST_DIR"
rm -rf "$PACKAGE_DIR" "$ZIP_PATH"
mkdir -p "$PACKAGE_DIR"

APP_SOURCE="$(CODEX_USAGE_ARCHS="$RELEASE_ARCHS" CODEX_USAGE_BUILD_PATH="${CODEX_USAGE_BUILD_PATH:-/tmp/codex-usage-menu-release-build}" "$ROOT_DIR/scripts/build-macos-app.sh")"
cp -R "$APP_SOURCE" "$PACKAGE_DIR/$APP_NAME.app"

cat > "$PACKAGE_DIR/install.command" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Codex 用量"
APP_SOURCE="$SCRIPT_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications"
PLIST="$HOME/Library/LaunchAgents/com.local.codex-usage-menu.plist"
LOG_DIR="$HOME/Library/Logs"

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "找不到 $APP_NAME.app，请确认 install.command 和 App 在同一个文件夹里。"
  exit 1
fi

if [[ ! -w "$INSTALL_DIR" ]]; then
  INSTALL_DIR="$HOME/Applications"
fi

mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents" "$LOG_DIR"
APP_DEST="$INSTALL_DIR/$APP_NAME.app"
APP_BINARY="$APP_DEST/Contents/MacOS/codex-usage-menu"

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
pkill -x codex-usage-menu 2>/dev/null || true

rm -rf "$APP_DEST"
cp -R "$APP_SOURCE" "$APP_DEST"
xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true
xattr -dr com.apple.provenance "$APP_DEST" 2>/dev/null || true

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.codex-usage-menu</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_BINARY</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/codex-usage-menu.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/codex-usage-menu.err.log</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/com.local.codex-usage-menu"
open -R "$APP_DEST"

echo
echo "安装完成：$APP_DEST"
echo "如果菜单栏没有立刻出现，请双击打开 $APP_NAME.app。"
SCRIPT

chmod +x "$PACKAGE_DIR/install.command"

cat > "$PACKAGE_DIR/README.txt" <<'TEXT'
Codex 用量 - macOS 安装说明

1. 双击 install.command 安装。
2. 如果 macOS 阻止打开，请右键 install.command，选择“打开”。
3. 安装后会出现在 /Applications/Codex 用量.app。
4. 它是菜单栏 App，打开后没有普通窗口，请看屏幕顶部菜单栏。
5. 需要这台 Mac 上已经使用过 Codex，并存在 ~/.codex/sessions 记录，才会显示真实用量。
6. 当前发布包是 universal 版本，适用于 Apple Silicon 和 Intel Mac。
TEXT

(
  cd "$DIST_DIR"
  COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$PACKAGE_NAME" "$ZIP_PATH"
)

echo "$ZIP_PATH"
