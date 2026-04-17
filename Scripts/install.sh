#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Model Switchboard.app"
LEGACY_APP_NAME="ModelSwitchboard.app"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
SYSTEM_APPLICATIONS_DIR="/Applications"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_APP="$ROOT_DIR/.xcodebuild/Build/Products/$CONFIGURATION/ModelSwitchboard.app"
DIST_APP="$ROOT_DIR/dist/$APP_NAME"
LEGACY_DIST_APP="$ROOT_DIR/dist/$LEGACY_APP_NAME"
INSTALL_APP="$INSTALL_DIR/$APP_NAME"
LEGACY_INSTALL_APP="$INSTALL_DIR/$LEGACY_APP_NAME"
SYSTEM_INSTALL_APP="$SYSTEM_APPLICATIONS_DIR/$APP_NAME"
LEGACY_SYSTEM_INSTALL_APP="$SYSTEM_APPLICATIONS_DIR/$LEGACY_APP_NAME"

cd "$ROOT_DIR"

mkdir -p "$INSTALL_DIR"

pkill -f 'ModelSwitchboard(\.app/Contents/MacOS/ModelSwitchboard|App)' >/dev/null 2>&1 || true
sleep 1

CONFIGURATION="$CONFIGURATION" "$ROOT_DIR/Scripts/build-xcode-app.sh" >/dev/null

rm -rf "$DIST_APP" "$LEGACY_DIST_APP" "$INSTALL_APP" "$LEGACY_INSTALL_APP"
cp -R "$DERIVED_APP" "$DIST_APP"
cp -R "$DERIVED_APP" "$INSTALL_APP"

if [ -w "$SYSTEM_APPLICATIONS_DIR" ]; then
  rm -rf "$SYSTEM_INSTALL_APP" "$LEGACY_SYSTEM_INSTALL_APP"
fi

xattr -dr com.apple.quarantine "$DIST_APP" >/dev/null 2>&1 || true
xattr -dr com.apple.quarantine "$INSTALL_APP" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$DIST_APP" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$INSTALL_APP" >/dev/null 2>&1 || true
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a E "$DIST_APP" >/dev/null 2>&1 || true
  SetFile -a E "$INSTALL_APP" >/dev/null 2>&1 || true
else
  osascript >/dev/null 2>&1 <<APPLESCRIPT || true
tell application "Finder"
  set extension hidden of (POSIX file "$DIST_APP" as alias) to true
  set extension hidden of (POSIX file "$INSTALL_APP" as alias) to true
end tell
APPLESCRIPT
fi

if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$INSTALL_APP" >/dev/null 2>&1 || true
fi

if command -v mdimport >/dev/null 2>&1; then
  mdimport -f "$INSTALL_APP" >/dev/null 2>&1 || true
fi

open -a "$INSTALL_APP"

printf 'installed=%s\n' "$INSTALL_APP"
printf 'dist=%s\n' "$DIST_APP"
