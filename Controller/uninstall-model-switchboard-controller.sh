#!/usr/bin/env bash
set -euo pipefail
LABEL="io.modelswitchboard.controller"
PLIST_DST="$HOME/Library/LaunchAgents/${LABEL}.plist"
USER_UID="$(id -u)"
DOMAIN="gui/${USER_UID}"
launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
launchctl bootout "$DOMAIN" "$PLIST_DST" >/dev/null 2>&1 || true
rm -f "$PLIST_DST"
printf 'removed=%s\n' "$PLIST_DST"
