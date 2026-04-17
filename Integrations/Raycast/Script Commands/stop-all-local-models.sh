#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Stop All Local Models
# @raycast.mode compact

# Optional parameters:
# @raycast.packageName Model Switchboard
# @raycast.icon ⛔️
# @raycast.description Stop every running model managed by the controller.

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
"$ROOT_DIR/Scripts/model-switchboardctl" stop-all >/dev/null
