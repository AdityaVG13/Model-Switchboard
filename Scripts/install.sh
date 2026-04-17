#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_VARIANT="${APP_VARIANT:-base}"
case "$APP_VARIANT" in
  base)
    APP_NAME="Model Switchboard.app"
    PRODUCT_NAME="ModelSwitchboard.app"
    LEGACY_APP_NAME="ModelSwitchboard.app"
    ;;
  plus)
    APP_NAME="Model Switchboard Plus.app"
    PRODUCT_NAME="ModelSwitchboardPlus.app"
    LEGACY_APP_NAME=""
    ;;
  *)
    echo "Unsupported APP_VARIANT: $APP_VARIANT" >&2
    exit 1
    ;;
esac
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
SYSTEM_APPLICATIONS_DIR="/Applications"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_APP="$ROOT_DIR/.xcodebuild/Build/Products/$CONFIGURATION/$PRODUCT_NAME"
DIST_APP="$ROOT_DIR/dist/$APP_NAME"
LEGACY_DIST_APP="${LEGACY_APP_NAME:+$ROOT_DIR/dist/$LEGACY_APP_NAME}"
INSTALL_APP="$INSTALL_DIR/$APP_NAME"
LEGACY_INSTALL_APP="${LEGACY_APP_NAME:+$INSTALL_DIR/$LEGACY_APP_NAME}"
SYSTEM_INSTALL_APP="$SYSTEM_APPLICATIONS_DIR/$APP_NAME"
LEGACY_SYSTEM_INSTALL_APP="${LEGACY_APP_NAME:+$SYSTEM_APPLICATIONS_DIR/$LEGACY_APP_NAME}"

cd "$ROOT_DIR"

mkdir -p "$INSTALL_DIR"

pkill -f 'ModelSwitchboard(Plus)?(\.app/Contents/MacOS/ModelSwitchboard(Plus)?|App)' >/dev/null 2>&1 || true
sleep 1

APP_VARIANT="$APP_VARIANT" CONFIGURATION="$CONFIGURATION" "$ROOT_DIR/Scripts/build-xcode-app.sh" >/dev/null

rm -rf "$DIST_APP" "$INSTALL_APP"
if [ -n "$LEGACY_DIST_APP" ]; then
  rm -rf "$LEGACY_DIST_APP" "$LEGACY_INSTALL_APP"
fi
cp -R "$DERIVED_APP" "$DIST_APP"
cp -R "$DERIVED_APP" "$INSTALL_APP"

if [ -w "$SYSTEM_APPLICATIONS_DIR" ]; then
  rm -rf "$SYSTEM_INSTALL_APP"
  if [ -n "$LEGACY_SYSTEM_INSTALL_APP" ]; then
    rm -rf "$LEGACY_SYSTEM_INSTALL_APP"
  fi
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
