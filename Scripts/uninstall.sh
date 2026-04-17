#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
SYSTEM_APPLICATIONS_DIR="/Applications"

APP_NAMES=(
  "Model Switchboard.app"
  "ModelSwitchboard.app"
)

pkill -f 'ModelSwitchboard(\.app/Contents/MacOS/ModelSwitchboard|App)' >/dev/null 2>&1 || true
sleep 1

for app_name in "${APP_NAMES[@]}"; do
  rm -rf "$ROOT_DIR/dist/$app_name"
  rm -rf "$INSTALL_DIR/$app_name"
  if [ -w "$SYSTEM_APPLICATIONS_DIR" ]; then
    rm -rf "$SYSTEM_APPLICATIONS_DIR/$app_name"
  fi
done

rm -f "$HOME/Library/Preferences/io.modelswitchboard.app.plist"
rm -f "$HOME/Library/Preferences/io.modelswitchboard.app.widget.plist"
rm -rf "$HOME/Library/Containers/io.modelswitchboard.app.widget"
rm -rf "$HOME/Library/Application Scripts/io.modelswitchboard.app.widget"

printf 'removed=%s\n' "$INSTALL_DIR/Model Switchboard.app"
