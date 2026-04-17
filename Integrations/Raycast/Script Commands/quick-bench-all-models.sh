#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Quick Bench All Models
# @raycast.mode compact

# Optional parameters:
# @raycast.packageName Model Switchboard
# @raycast.icon ⚡️
# @raycast.description Start the quick benchmark suite across all profiles.

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
"$ROOT_DIR/Scripts/model-switchboardctl" bench-all >/dev/null
