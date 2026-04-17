#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.xcodebuild"
CONFIGURATION="${CONFIGURATION:-Debug}"
PROJECT_FILE="$ROOT_DIR/ModelSwitchboard.xcodeproj"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
BUILD_NUMBER="${BUILD_NUMBER:-$VERSION}"
APP_VARIANT="${APP_VARIANT:-base}"

case "$APP_VARIANT" in
  base)
    SCHEME_NAME="ModelSwitchboard"
    PRODUCT_NAME="ModelSwitchboard"
    ;;
  plus)
    SCHEME_NAME="ModelSwitchboardPlus"
    PRODUCT_NAME="ModelSwitchboardPlus"
    ;;
  *)
    echo "Unsupported APP_VARIANT: $APP_VARIANT" >&2
    exit 1
    ;;
esac

cd "$ROOT_DIR"

"$ROOT_DIR/Scripts/generate-app-icon.sh" >/dev/null

# Keep the Xcode project in sync with the source tree. New Swift files do not
# automatically appear in an existing .xcodeproj unless we regenerate it.
if [ "${SKIP_XCODEGEN:-0}" != "1" ]; then
  "$ROOT_DIR/Scripts/generate-xcodeproj.sh"
fi
xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  build
printf 'app=%s\n' "$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$PRODUCT_NAME.app"
