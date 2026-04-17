#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open Model Switchboard
# @raycast.mode compact

# Optional parameters:
# @raycast.packageName Model Switchboard
# @raycast.icon 🧭
# @raycast.description Launch the menu bar app.

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
"$ROOT_DIR/Scripts/model-switchboardctl" open-app >/dev/null
