#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SVG_SOURCE="$ROOT_DIR/Resources/App/ModelSwitchboardIcon.svg"
ICONSET_DIR="$ROOT_DIR/Resources/App/ModelSwitchboard.iconset"
ICON_FILE="$ROOT_DIR/Resources/App/ModelSwitchboard.icns"
TEMP_DIR="${TMPDIR:-/tmp}/modelswitchboard-icon.$$"
BASE_PNG="$TEMP_DIR/base.png"
mkdir -p "$TEMP_DIR" "$ICONSET_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

qlmanage -t -s 1024 -o "$TEMP_DIR" "$SVG_SOURCE" >/dev/null 2>&1
mv "$TEMP_DIR/$(basename "$SVG_SOURCE").png" "$BASE_PNG"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$BASE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$BASE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
printf 'icon=%s\n' "$ICON_FILE"
