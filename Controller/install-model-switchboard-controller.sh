#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      shift
      [ "$#" -gt 0 ] || die "--root requires a path"
      ROOT_DIR="$1"
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
  shift
done

ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"
LABEL="io.modelswitchboard.controller"
PLIST_DST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LAUNCHER_SRC="$ROOT_DIR/ModelSwitchboardController.swift"
LAUNCHER_BIN="$ROOT_DIR/bin/ModelSwitchboardController"
USER_UID="$(id -u)"
DOMAIN="gui/${USER_UID}"

[ -f "$LAUNCHER_SRC" ] || die "launcher source not found: $LAUNCHER_SRC"

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$ROOT_DIR/bin"

if [ ! -x "$LAUNCHER_BIN" ] || [ "$LAUNCHER_SRC" -nt "$LAUNCHER_BIN" ]; then
  swiftc -O -o "$LAUNCHER_BIN" "$LAUNCHER_SRC"
fi

cat >"$PLIST_DST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${LAUNCHER_BIN}</string>
    <string>--root</string>
    <string>${ROOT_DIR}</string>
    <string>--host</string>
    <string>127.0.0.1</string>
    <string>--port</string>
    <string>8877</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${ROOT_DIR}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/model-switchboard-controller.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/model-switchboard-controller.log</string>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
PLIST
chmod 644 "$PLIST_DST"
launchctl bootout "$DOMAIN" "$PLIST_DST" >/dev/null 2>&1 || true
launchctl bootstrap "$DOMAIN" "$PLIST_DST"
launchctl kickstart -k "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
printf 'installed=%s\n' "$PLIST_DST"
