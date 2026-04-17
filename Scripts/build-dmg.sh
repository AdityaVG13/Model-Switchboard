#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_NAME="Model Switchboard.app"
VOL_NAME="Model Switchboard $VERSION"
DIST_DIR="$ROOT_DIR/dist"
SOURCE_APP="$DIST_DIR/$APP_NAME"
DMG_PATH="$DIST_DIR/Model-Switchboard-$VERSION.dmg"
STAGING_DIR="$(mktemp -d "$DIST_DIR/dmg-stage.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  "$ROOT_DIR/Scripts/build-app.sh" >/dev/null
fi

rm -f "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$SOURCE_APP" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDZO \
  "$DMG_PATH" >/dev/null

printf 'dmg=%s\n' "$DMG_PATH"
