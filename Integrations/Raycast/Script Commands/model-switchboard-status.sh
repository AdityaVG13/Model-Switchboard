#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Model Switchboard Status
# @raycast.mode inline
# @raycast.refreshTime 15s

# Optional parameters:
# @raycast.packageName Model Switchboard
# @raycast.icon 💻
# @raycast.description Show local model readiness and running state.

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
"$ROOT_DIR/Scripts/model-switchboardctl" summary | head -1
