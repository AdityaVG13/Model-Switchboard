#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Model Switchboard.app"
SOURCE_APP="$ROOT_DIR/.xcodebuild/Build/Products/$CONFIGURATION/ModelSwitchboard.app"
TARGET_APP="$DIST_DIR/$APP_NAME"

cd "$ROOT_DIR"
CONFIGURATION="$CONFIGURATION" "$ROOT_DIR/Scripts/build-xcode-app.sh" >/dev/null

rm -rf "$TARGET_APP"
mkdir -p "$DIST_DIR"
cp -R "$SOURCE_APP" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$TARGET_APP" >/dev/null 2>&1 || true

printf 'app=%s\n' "$TARGET_APP"
