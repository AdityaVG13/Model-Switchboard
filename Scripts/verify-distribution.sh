#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_PATH="${1:-$ROOT_DIR/dist/Model Switchboard.app}"
DMG_PATH="${2:-$ROOT_DIR/dist/Model-Switchboard-$VERSION.dmg}"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

SIGNATURE_INFO="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 || true)"
if grep -q "Authority=Developer ID Application" <<<"$SIGNATURE_INFO"; then
  spctl -a -vv --type exec "$APP_PATH"
else
  echo "note: skipping Gatekeeper exec assessment for local ad hoc build"
fi

if [ -f "$DMG_PATH" ]; then
  if grep -q "Authority=Developer ID Application" <<<"$SIGNATURE_INFO"; then
    spctl -a -vv --type open "$DMG_PATH"
  else
    echo "note: skipping Gatekeeper DMG assessment for local ad hoc build"
  fi
fi

printf 'verified_app=%s\n' "$APP_PATH"
if [ -f "$DMG_PATH" ]; then
  printf 'verified_dmg=%s\n' "$DMG_PATH"
fi
