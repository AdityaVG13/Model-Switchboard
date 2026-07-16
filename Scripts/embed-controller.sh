#!/usr/bin/env bash
# Embed the native controller binary, support scripts, and LaunchAgent into an
# already-built .app bundle. Used by build-app.sh and build-xcode-app.sh so Debug
# / Xcode runs cannot ship a UI-only bundle that cannot start the controller.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${1:?Usage: embed-controller.sh /path/to/App.app}"

if [ ! -d "$APP_BUNDLE/Contents" ]; then
  echo "embed-controller: not an app bundle: $APP_BUNDLE" >&2
  exit 1
fi

cd "$ROOT_DIR"
CONTROLLER_BIN_DIR="$(swift build -c release --show-bin-path)"
swift build -c release --product ModelSwitchboardController >/dev/null

mkdir -p \
  "$APP_BUNDLE/Contents/Resources/ControllerSupport/model-profiles" \
  "$APP_BUNDLE/Contents/Library/LaunchAgents"

cp "$CONTROLLER_BIN_DIR/ModelSwitchboardController" \
  "$APP_BUNDLE/Contents/Resources/ModelSwitchboardController"
cp "$ROOT_DIR/Controller/start-model-mac.sh" "$ROOT_DIR/Controller/stop-all-models.sh" \
  "$APP_BUNDLE/Contents/Resources/ControllerSupport/"
rm -rf "$APP_BUNDLE/Contents/Resources/ControllerSupport/model-profiles/examples"
cp -R "$ROOT_DIR/Controller/model-profiles/examples" \
  "$APP_BUNDLE/Contents/Resources/ControllerSupport/model-profiles/examples"
cp "$ROOT_DIR/Resources/Controller/io.modelswitchboard.controller.plist" \
  "$APP_BUNDLE/Contents/Library/LaunchAgents/"
chmod 755 \
  "$APP_BUNDLE/Contents/Resources/ModelSwitchboardController" \
  "$APP_BUNDLE/Contents/Resources/ControllerSupport/"*.sh

printf 'embedded_controller=%s\n' "$APP_BUNDLE/Contents/Resources/ModelSwitchboardController"
