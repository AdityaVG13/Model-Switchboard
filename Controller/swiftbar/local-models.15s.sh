#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONTROLLER_BIN="${MODEL_SWITCHBOARD_CONTROLLER_BIN:-$ROOT_DIR/bin/ModelSwitchboardController}"
if [ ! -x "$CONTROLLER_BIN" ]; then
  CONTROLLER_BIN="$HOME/Applications/Model Switchboard.app/Contents/Resources/ModelSwitchboardController"
fi
if [ ! -x "$CONTROLLER_BIN" ]; then
  printf 'LLMs unavailable\n---\nNative controller not found\n'
  exit 0
fi
"$CONTROLLER_BIN" swiftbar --root "$ROOT_DIR" 2>/dev/null || printf 'LLMs unavailable\n---\nController request failed\n'
