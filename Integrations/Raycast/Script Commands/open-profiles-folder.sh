#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open Profiles Folder
# @raycast.mode compact

# Optional parameters:
# @raycast.packageName Model Switchboard
# @raycast.icon 📁
# @raycast.description Open the controller's live model-profiles directory.

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
"$ROOT_DIR/Scripts/model-switchboardctl" open-profiles >/dev/null
