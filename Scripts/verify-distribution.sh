#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_VARIANT="${APP_VARIANT:-base}"
case "$APP_VARIANT" in
  base)
    DEFAULT_APP_PATH="$ROOT_DIR/dist/Model Switchboard.app"
    DEFAULT_DMG_PATH="$ROOT_DIR/dist/Model-Switchboard-$VERSION.dmg"
    ;;
  plus)
    DEFAULT_APP_PATH="$ROOT_DIR/dist/Model Switchboard Plus.app"
    DEFAULT_DMG_PATH="$ROOT_DIR/dist/Model-Switchboard-Plus-$VERSION.dmg"
    ;;
  *)
    echo "Unsupported APP_VARIANT: $APP_VARIANT" >&2
    exit 1
    ;;
esac
APP_PATH="${1:-$DEFAULT_APP_PATH}"
DMG_PATH="${2:-$DEFAULT_DMG_PATH}"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
"$ROOT_DIR/Scripts/verify-privacy.sh" "$APP_PATH"

SIGNATURE_INFO="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 || true)"
if grep -q "Authority=Developer ID Application" <<<"$SIGNATURE_INFO"; then
  spctl -a -vv --type exec "$APP_PATH"
else
  echo "note: skipping Gatekeeper exec assessment for local ad hoc build"
fi

if [ -f "$DMG_PATH" ]; then
  if grep -q "Authority=Developer ID Application" <<<"$SIGNATURE_INFO"; then
    xcrun stapler validate "$DMG_PATH"
    DMG_ASSESSMENT="$(spctl -a -vv --type open "$DMG_PATH" 2>&1 || true)"
    if grep -q "source=Insufficient Context" <<<"$DMG_ASSESSMENT"; then
      echo "note: Gatekeeper DMG assessment returned Insufficient Context; stapler validation succeeded"
    else
      echo "$DMG_ASSESSMENT"
      if ! grep -q ": accepted" <<<"$DMG_ASSESSMENT"; then
        echo "DMG Gatekeeper assessment failed" >&2
        exit 1
      fi
    fi
  else
    echo "note: skipping Gatekeeper DMG assessment for local ad hoc build"
  fi
fi

printf 'verified_app=%s\n' "$APP_PATH"
if [ -f "$DMG_PATH" ]; then
  printf 'verified_dmg=%s\n' "$DMG_PATH"
fi
