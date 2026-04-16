#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.xcodebuild"
cd "$ROOT_DIR"
if [ ! -d "$ROOT_DIR/ModelSwitchboard.xcodeproj" ]; then
  "$ROOT_DIR/Scripts/generate-xcodeproj.sh"
fi
xcodebuild \
  -project "$ROOT_DIR/ModelSwitchboard.xcodeproj" \
  -scheme ModelSwitchboard \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build
printf 'app=%s\n' "$DERIVED_DATA_DIR/Build/Products/Debug/ModelSwitchboard.app"
