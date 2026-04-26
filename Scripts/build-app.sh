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

strip_macho_binaries() {
  local bundle_path="$1"
  local candidate
  local description

  while IFS= read -r -d '' candidate; do
    description="$(file -b "$candidate" 2>/dev/null || true)"
    if [[ "$description" == *"Mach-O"* ]]; then
      xcrun strip -S -x "$candidate" >/dev/null
    fi
  done < <(find "$bundle_path" -type f -print0)
}

cd "$ROOT_DIR"
APP_VARIANT="$APP_VARIANT" CONFIGURATION="$CONFIGURATION" "$ROOT_DIR/Scripts/build-xcode-app.sh" >/dev/null

rm -rf "$TARGET_APP"
mkdir -p "$DIST_DIR"
cp -R "$SOURCE_APP" "$TARGET_APP"
strip_macho_binaries "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$TARGET_APP" >/dev/null 2>&1 || true

printf 'app=%s\n' "$TARGET_APP"
