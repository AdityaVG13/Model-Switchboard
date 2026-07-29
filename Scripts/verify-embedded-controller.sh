#!/usr/bin/env bash
# Verify that an .app bundle embeds ModelSwitchboardController + its LaunchAgent.
# Shared by install.sh and verify-distribution.sh.
set -euo pipefail

APP_PATH="${1:?Usage: verify-embedded-controller.sh /path/to/App.app}"

if [ ! -d "$APP_PATH/Contents" ]; then
  echo "verify-embedded-controller: not an app bundle: $APP_PATH" >&2
  exit 1
fi

CONTROLLER_BIN="$APP_PATH/Contents/Resources/ModelSwitchboardController"
CONTROLLER_PLIST="$APP_PATH/Contents/Library/LaunchAgents/io.modelswitchboard.controller.plist"

[ -x "$CONTROLLER_BIN" ] || {
  echo "embedded controller missing: $CONTROLLER_BIN" >&2
  exit 1
}
[ -f "$CONTROLLER_PLIST" ] || {
  echo "controller LaunchAgent missing: $CONTROLLER_PLIST" >&2
  exit 1
}

printf 'embedded_controller_ok=%s\n' "$APP_PATH"
