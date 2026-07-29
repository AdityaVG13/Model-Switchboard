#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_VARIANT="${APP_VARIANT:-base}"
case "$APP_VARIANT" in
  base)
    APP_NAME="Model Switchboard.app"
    DMG_NAME="Model-Switchboard-$VERSION.dmg"
    ;;
  plus)
    APP_NAME="Model Switchboard Plus.app"
    DMG_NAME="Model-Switchboard-Plus-$VERSION.dmg"
    ;;
  *)
    echo "Unsupported APP_VARIANT: $APP_VARIANT" >&2
    exit 1
    ;;
esac
APP_PATH="$ROOT_DIR/dist/$APP_NAME"
DMG_PATH="$ROOT_DIR/dist/$DMG_NAME"
IDENTITY="${APPLE_DEVELOPER_IDENTITY:?set APPLE_DEVELOPER_IDENTITY}"
NOTARY_PROFILE="${APPLE_NOTARY_KEYCHAIN_PROFILE:-}"
API_KEY_PATH="${APPLE_NOTARY_API_KEY_PATH:-}"
API_KEY_ID="${APPLE_NOTARY_API_KEY_ID:-}"
API_ISSUER_ID="${APPLE_NOTARY_API_ISSUER_ID:-}"

cd "$ROOT_DIR"

APP_VARIANT="$APP_VARIANT" "$ROOT_DIR/Scripts/build-app.sh" >/dev/null

# Sign the embedded controller binary individually before the outer app. The
# SwiftPM-built controller is an unsigned Mach-O copied into Contents/Resources/
# by embed-controller.sh; `codesign --deep` on the app only seals it as a
# resource, which Apple rejects ("not signed with a valid Developer ID certificate",
# "no secure timestamp", "hardened runtime not enabled"). Sign inside-out with
# the identity, hardened runtime, and secure timestamp so the binary passes
# notarization and the outer --deep sign preserves it.
CONTROLLER_BIN="$APP_PATH/Contents/Resources/ModelSwitchboardController"
if [ -f "$CONTROLLER_BIN" ]; then
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$IDENTITY" \
    "$CONTROLLER_BIN"
fi

codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --sign "$IDENTITY" \
  "$APP_PATH"
"$ROOT_DIR/Scripts/verify-privacy.sh" "$APP_PATH"

APP_VARIANT="$APP_VARIANT" SKIP_BUILD=1 "$ROOT_DIR/Scripts/build-dmg.sh" >/dev/null

if [ -n "$NOTARY_PROFILE" ]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
elif [ -n "$API_KEY_PATH" ] && [ -n "$API_KEY_ID" ] && [ -n "$API_ISSUER_ID" ]; then
  xcrun notarytool submit \
    "$DMG_PATH" \
    --key "$API_KEY_PATH" \
    --key-id "$API_KEY_ID" \
    --issuer "$API_ISSUER_ID" \
    --wait
else
  echo "missing notarization credentials: set APPLE_NOTARY_KEYCHAIN_PROFILE or API key variables" >&2
  exit 1
fi

xcrun stapler staple "$DMG_PATH"

printf 'signed_app=%s\n' "$APP_PATH"
printf 'notarized_dmg=%s\n' "$DMG_PATH"
