#!/usr/bin/env bash
# Verify that an .app bundle embeds ModelSwitchboardController + its LaunchAgent.
# Shared by install.sh and verify-distribution.sh.
set -euo pipefail

APP_PATH="${1:?Usage: verify-embedded-controller.sh /path/to/App.app}"

if [ ! -d "$APP_PATH/Contents" ]; then
  echo "verify-embedded-controller: not an app bundle: $APP_PATH" >&2
  exit 1
fi

CONTROLLER_BIN="$APP_PATH/Contents/Resources/ModelSwitchboardController"
CONTROLLER_PLIST="$APP_PATH/Contents/Library/LaunchAgents/io.modelswitchboard.controller.plist"
REMOTE_AGENT_PY="$APP_PATH/Contents/Resources/RemoteAgent/model_switchboard_agent.py"
REMOTE_AGENT_DISCOVERY="$APP_PATH/Contents/Resources/RemoteAgent/discovery.py"
REMOTE_AGENT_INSTALLER="$APP_PATH/Contents/Resources/RemoteAgent/install-remote-agent.sh"

[ -x "$CONTROLLER_BIN" ] || {
  echo "embedded controller missing: $CONTROLLER_BIN" >&2
  exit 1
}
[ -f "$CONTROLLER_PLIST" ] || {
  echo "controller LaunchAgent missing: $CONTROLLER_PLIST" >&2
  exit 1
}
[ -f "$REMOTE_AGENT_PY" ] || {
  echo "embedded remote agent missing: $REMOTE_AGENT_PY" >&2
  exit 1
}
[ -f "$REMOTE_AGENT_DISCOVERY" ] || {
  echo "embedded remote agent discovery module missing: $REMOTE_AGENT_DISCOVERY" >&2
  exit 1
}
[ -x "$REMOTE_AGENT_INSTALLER" ] || {
  echo "embedded remote agent installer missing or not executable: $REMOTE_AGENT_INSTALLER" >&2
  exit 1
}

printf 'embedded_controller_ok=%s\n' "$APP_PATH"
