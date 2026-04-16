#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8877}"
LOG_PATH="/tmp/model-dashboard.log"
URL="http://${HOST}:${PORT}/"
LAUNCHER_SRC="$ROOT_DIR/ModelSwitchboardController.swift"
LAUNCHER_BIN="$ROOT_DIR/bin/ModelSwitchboardController"

mkdir -p "$ROOT_DIR/bin"

if [ ! -x "$LAUNCHER_BIN" ] || [ "$LAUNCHER_SRC" -nt "$LAUNCHER_BIN" ]; then
  swiftc -O -o "$LAUNCHER_BIN" "$LAUNCHER_SRC"
fi

if ! lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  nohup "$LAUNCHER_BIN" --root "$ROOT_DIR" --host "$HOST" --port "$PORT" >"$LOG_PATH" 2>&1 &
  sleep 1
fi

open "$URL"
