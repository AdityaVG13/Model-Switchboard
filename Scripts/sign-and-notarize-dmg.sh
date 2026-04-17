#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_NAME="Model Switchboard.app"
APP_PATH="$ROOT_DIR/dist/$APP_NAME"
DMG_PATH="$ROOT_DIR/dist/Model-Switchboard-$VERSION.dmg"
IDENTITY="${APPLE_DEVELOPER_IDENTITY:?set APPLE_DEVELOPER_IDENTITY}"
NOTARY_PROFILE="${APPLE_NOTARY_KEYCHAIN_PROFILE:-}"
API_KEY_PATH="${APPLE_NOTARY_API_KEY_PATH:-}"
API_KEY_ID="${APPLE_NOTARY_API_KEY_ID:-}"
API_ISSUER_ID="${APPLE_NOTARY_API_ISSUER_ID:-}"

cd "$ROOT_DIR"

"$ROOT_DIR/Scripts/build-app.sh" >/dev/null

codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --sign "$IDENTITY" \
  "$APP_PATH"

SKIP_BUILD=1 "$ROOT_DIR/Scripts/build-dmg.sh" >/dev/null

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
