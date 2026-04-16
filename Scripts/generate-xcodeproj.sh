#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
xcodegen generate
printf 'project=%s\n' "$ROOT_DIR/ModelSwitchboard.xcodeproj"
