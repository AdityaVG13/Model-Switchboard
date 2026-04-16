#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CTL="$ROOT_DIR/modelctl.py"
DASHBOARD="$ROOT_DIR/start-model-dashboard.sh"
STATUS_JSON="$($CTL status --json 2>/dev/null || echo '{"statuses": []}')"

STATUS_JSON="$STATUS_JSON" python3 - "$CTL" "$DASHBOARD" <<'PY'
import json
import os
import sys

ctl = sys.argv[1]
dashboard = sys.argv[2]
data = json.loads(os.environ.get("STATUS_JSON", "{}") or "{}")
statuses = data.get("statuses", [])
running = sum(1 for item in statuses if item.get("running"))
ready = sum(1 for item in statuses if item.get("ready"))
total = len(statuses)
integrations = data.get("integrations", [])

print(f"LLMs {ready}/{total}")
print("---")
print(f"Ready endpoints: {ready}/{total}")
print(f"Running processes: {running}")
print(f"Open dashboard | bash={dashboard} terminal=false refresh=false")
print(f"Refresh now | bash={ctl} param1=status terminal=false refresh=true")
for integration in integrations:
    if "sync" in integration.get("capabilities", []):
        label = integration.get("sync_label") or f"Sync {integration.get('display_name', integration.get('id', 'integration'))}"
        ident = integration["id"]
        print(f"{label} | bash={ctl} param1=run-integration param2={ident} terminal=false refresh=true")
print(f"Stop all | bash={ctl} param1=stop-all terminal=false refresh=true color=red")
print("---")

for item in statuses:
    state = "RUNNING" if item.get("running") else "NOT RUNNING"
    color = "green" if item.get("ready") else ("orange" if item.get("running") else "red")
    profile = item["profile"]
    title = item["display_name"].replace("|", "/")
    print(f"{title} [{state}] | color={color}")
    print(f"Start {profile} | bash={ctl} param1=start param2={profile} terminal=false refresh=true")
    print(f"Stop {profile} | bash={ctl} param1=stop param2={profile} terminal=false refresh=true")
    print(f"Restart {profile} | bash={ctl} param1=restart param2={profile} terminal=false refresh=true")
    print(f"Port {item['port']} • PID {item.get('pid') or '-'} • RSS {item.get('rss_mb') or 'n/a'} MB")
    print("---")
PY
