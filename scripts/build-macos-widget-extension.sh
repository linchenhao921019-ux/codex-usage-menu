#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$("$ROOT_DIR/scripts/build-macos-app.sh")"
APPEX_PATH="$APP_PATH/Contents/PlugIns/CodexUsageMacWidgetExtension.appex"

if [[ ! -d "$APPEX_PATH" ]]; then
  echo "Missing macOS widget extension: $APPEX_PATH" >&2
  exit 1
fi

echo "$APPEX_PATH"
