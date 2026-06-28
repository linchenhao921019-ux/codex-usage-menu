#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${CODEX_USAGE_APP_NAME:-Codex 用量}"
PLIST="$HOME/Library/LaunchAgents/com.local.codex-usage-menu.plist"
LOG_DIR="$HOME/Library/Logs"
DEFAULT_INSTALL_DIR="/Applications"
INSTALL_DIR="${CODEX_USAGE_APP_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"

if [[ ! -w "$INSTALL_DIR" ]]; then
  INSTALL_DIR="$HOME/Applications"
fi

mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents" "$LOG_DIR"

APP_SOURCE="$("$ROOT_DIR/scripts/build-macos-app.sh")"
APP_DEST="$INSTALL_DIR/$APP_NAME.app"
APP_BINARY="$APP_DEST/Contents/MacOS/codex-usage-menu"

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
pkill -x codex-usage-menu 2>/dev/null || true

rm -rf "$APP_DEST"
cp -R "$APP_SOURCE" "$APP_DEST"
codesign --force --deep --sign - "$APP_DEST" >/dev/null
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

echo "Installed: $APP_DEST"
echo "Started LaunchAgent: $PLIST"
