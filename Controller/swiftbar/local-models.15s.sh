#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONTROLLER_BIN="${MODEL_SWITCHBOARD_CONTROLLER_BIN:-$ROOT_DIR/bin/ModelSwitchboardController}"
if [ ! -x "$CONTROLLER_BIN" ]; then
  for candidate in \
    "/Applications/Model Switchboard.app/Contents/Resources/ModelSwitchboardController" \
    "$HOME/Applications/Model Switchboard.app/Contents/Resources/ModelSwitchboardController" \
    "/Applications/Model Switchboard Plus.app/Contents/Resources/ModelSwitchboardController" \
    "$HOME/Applications/Model Switchboard Plus.app/Contents/Resources/ModelSwitchboardController"
  do
    if [ -x "$candidate" ]; then CONTROLLER_BIN="$candidate"; break; fi
  done
fi
if [ ! -x "$CONTROLLER_BIN" ]; then
  printf 'LLMs unavailable\n---\nNative controller not found\n'
  exit 0
fi
"$CONTROLLER_BIN" swiftbar --root "$ROOT_DIR" 2>/dev/null || printf 'LLMs unavailable\n---\nController request failed\n'
