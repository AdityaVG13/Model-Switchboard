#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_VARIANT="${APP_VARIANT:-base}"
DIST_DIR="$ROOT_DIR/dist"
case "$APP_VARIANT" in
  base)
    APP_NAME="Model Switchboard.app"
    PRODUCT_NAME="ModelSwitchboard.app"
    ;;
  plus)
    APP_NAME="Model Switchboard Plus.app"
    PRODUCT_NAME="ModelSwitchboardPlus.app"
    ;;
  *)
    echo "Unsupported APP_VARIANT: $APP_VARIANT" >&2
    exit 1
    ;;
esac
SOURCE_APP="$ROOT_DIR/.xcodebuild/Build/Products/$CONFIGURATION/$PRODUCT_NAME"
TARGET_APP="$DIST_DIR/$APP_NAME"

cd "$ROOT_DIR"
APP_VARIANT="$APP_VARIANT" CONFIGURATION="$CONFIGURATION" "$ROOT_DIR/Scripts/build-xcode-app.sh" >/dev/null

rm -rf "$TARGET_APP"
mkdir -p "$DIST_DIR"
cp -R "$SOURCE_APP" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$TARGET_APP" >/dev/null 2>&1 || true

printf 'app=%s\n' "$TARGET_APP"
