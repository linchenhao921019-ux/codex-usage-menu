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

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
pkill -x codex-usage-menu 2>/dev/null || true
pkill -x "$APP_NAME" 2>/dev/null || true

rm -rf "$APP_DEST"
ditto "$APP_SOURCE" "$APP_DEST"
xattr -cr "$APP_DEST" 2>/dev/null || true
xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true
xattr -dr com.apple.provenance "$APP_DEST" 2>/dev/null || true
WIDGET_EXTENSION="$APP_DEST/Contents/PlugIns/CodexUsageMacWidgetExtension.appex"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "$APP_DEST" 2>/dev/null || true
if [[ -d "$WIDGET_EXTENSION" ]] && command -v pluginkit >/dev/null; then
  pluginkit -r "$WIDGET_EXTENSION" >/dev/null 2>&1 || true
  pluginkit -a "$WIDGET_EXTENSION" >/dev/null 2>&1 || true
  pluginkit -e use -i com.local.codexusage.menu.widget >/dev/null 2>&1 || true
fi

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.codex-usage-menu</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-g</string>
    <string>-W</string>
    <string>$APP_DEST</string>
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
