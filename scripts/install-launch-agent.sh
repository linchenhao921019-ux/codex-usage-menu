#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.local.codex-usage-menu.plist"
BUILD_PATH="${CODEX_USAGE_BUILD_PATH:-/tmp/codex-usage-menu-build}"
INSTALL_DIR="$HOME/Library/Application Support/CodexUsageMenu/bin"
INSTALL_BINARY="$INSTALL_DIR/codex-usage-menu"

cd "$ROOT_DIR"
swift build -c release --build-path "$BUILD_PATH"
BINARY="$(swift build -c release --build-path "$BUILD_PATH" --show-bin-path)/codex-usage-menu"

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$INSTALL_DIR"
cp "$BINARY" "$INSTALL_BINARY"
chmod +x "$INSTALL_BINARY"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.codex-usage-menu</string>
  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_BINARY</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/codex-usage-menu.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/codex-usage-menu.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/com.local.codex-usage-menu"
echo "Installed and started: $PLIST"
