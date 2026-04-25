#!/usr/bin/env zsh
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

APP_VARIANT="${APP_VARIANT:-base}"
case "$APP_VARIANT" in
  base)
    APP_NAME="Model Switchboard"
    APP_BINARY_NAME="ModelSwitchboard"
    APP_BUNDLE_ID="io.modelswitchboard.app"
    HAS_ADVANCED=0
    ;;
  plus)
    APP_NAME="Model Switchboard Plus"
    APP_BINARY_NAME="ModelSwitchboardPlus"
    APP_BUNDLE_ID="io.modelswitchboard.plus"
    HAS_ADVANCED=1
    ;;
  *)
    echo "error: unsupported APP_VARIANT: $APP_VARIANT" >&2
    exit 1
    ;;
esac
APP_PATH="${MSW_APP_PATH:-$HOME/Applications/$APP_NAME.app}"
if [[ ! -d "$APP_PATH" ]]; then
  APP_PATH="/Applications/$APP_NAME.app"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: could not find installed app bundle" >&2
  exit 1
fi

CONTROLLER_URL="${MSW_CONTROLLER_URL:-http://127.0.0.1:8877}"
DEFAULT_CONTROLLER_URL="http://127.0.0.1:8877"
DROID_SETTINGS="$HOME/.factory/settings.json"
MSW_VERIFY_UI="${MSW_VERIFY_UI:-1}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cat <<'SWIFT' >"$WORK_DIR/msw_click.swift"
import Foundation
import CoreGraphics
if CommandLine.arguments.count != 3 { exit(2) }
let x = Double(CommandLine.arguments[1])!
let y = Double(CommandLine.arguments[2])!
let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)
let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
down?.post(tap: .cghidEventTap)
up?.post(tap: .cghidEventTap)
SWIFT

cat <<'SWIFT' >"$WORK_DIR/msw_window_bounds.swift"
import Foundation
import CoreGraphics
let target = CommandLine.arguments.dropFirst().joined(separator: " ")
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    let name = window[kCGWindowName as String] as? String ?? ""
    if owner == (ProcessInfo.processInfo.environment["MSW_APP_NAME"] ?? "") && (target.isEmpty || name == target) {
        let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let x = bounds["X"] as? Double ?? 0
        let y = bounds["Y"] as? Double ?? 0
        let w = bounds["Width"] as? Double ?? 0
        let h = bounds["Height"] as? Double ?? 0
        print("\(name)|\(x)|\(y)|\(w)|\(h)")
    }
}
SWIFT

cat <<'SWIFT' >"$WORK_DIR/msw_axpress.swift"
import Foundation
import ApplicationServices

let pid = pid_t(ProcessInfo.processInfo.environment["MSW_PID"]!)!
let targetWindow = ProcessInfo.processInfo.environment["MSW_WINDOW"] ?? ""
let targetDesc = ProcessInfo.processInfo.environment["MSW_DESC"] ?? ""
let targetIndex = Int(ProcessInfo.processInfo.environment["MSW_INDEX"] ?? "1") ?? 1

func value<T>(_ element: AXUIElement, _ attr: String, as type: T.Type) -> T? {
    var ref: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, attr as CFString, &ref)
    guard err == .success, let ref else { return nil }
    return ref as? T
}

func stringValue(_ element: AXUIElement, _ attr: String) -> String {
    value(element, attr, as: String.self) ?? ""
}

func labels(for element: AXUIElement) -> [String] {
    [
        kAXDescriptionAttribute as String,
        kAXTitleAttribute as String,
        kAXValueAttribute as String,
        kAXHelpAttribute as String,
        kAXIdentifierAttribute as String,
    ].map { stringValue(element, $0) }
}

func childElements(of element: AXUIElement) -> [AXUIElement] {
    [
        kAXChildrenAttribute as String,
        kAXVisibleChildrenAttribute as String,
        kAXContentsAttribute as String,
    ].flatMap { value(element, $0, as: [AXUIElement].self) ?? [] }
}

func containsLabel(_ element: AXUIElement, _ target: String, depth: Int = 0) -> Bool {
    if labels(for: element).contains(target) {
        return true
    }
    if depth >= 8 {
        return false
    }
    for child in childElements(of: element) {
        if containsLabel(child, target, depth: depth + 1) {
            return true
        }
    }
    return false
}

func findButtons(in element: AXUIElement, matches: inout [AXUIElement]) {
    let role = value(element, kAXRoleAttribute, as: String.self) ?? ""
    if role == kAXButtonRole as String && containsLabel(element, targetDesc) {
        matches.append(element)
    }
    for child in childElements(of: element) {
        findButtons(in: child, matches: &matches)
    }
}

let app = AXUIElementCreateApplication(pid)
let windows = value(app, kAXWindowsAttribute, as: [AXUIElement].self) ?? []
var matches: [AXUIElement] = []
for window in windows {
    let title = value(window, kAXTitleAttribute, as: String.self) ?? ""
    if targetWindow.isEmpty || title == targetWindow {
        findButtons(in: window, matches: &matches)
    }
}
if matches.count < targetIndex {
    fputs("no match\n", stderr)
    exit(1)
}
let result = AXUIElementPerformAction(matches[targetIndex - 1], kAXPressAction as CFString)
if result != .success && result != .notificationUnsupported {
    fputs("press failed \(result.rawValue)\n", stderr)
    exit(2)
}
SWIFT

cat <<'SWIFT' >"$WORK_DIR/msw_ocr.swift"
import AppKit
import Vision
import Foundation

guard CommandLine.arguments.count >= 3 else { exit(2) }
let imagePath = CommandLine.arguments[1]
let query = CommandLine.arguments.dropFirst(2).joined(separator: " ").lowercased()

guard let image = NSImage(contentsOfFile: imagePath),
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let cg = rep.cgImage else {
    exit(3)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
let handler = VNImageRequestHandler(cgImage: cg, options: [:])
try handler.perform([request])

struct TextBox {
    let text: String
    let centerX: Double
    let centerY: Double
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double
}

var boxes: [TextBox] = []
for obs in request.results ?? [] {
    guard let candidate = obs.topCandidates(1).first else { continue }
    let text = candidate.string
    let box = obs.boundingBox
    let minX = box.origin.x * Double(rep.pixelsWide)
    let maxX = (box.origin.x + box.size.width) * Double(rep.pixelsWide)
    let minY = (1.0 - (box.origin.y + box.size.height)) * Double(rep.pixelsHigh)
    let maxY = (1.0 - box.origin.y) * Double(rep.pixelsHigh)
    let centerX = (minX + maxX) / 2.0
    let centerY = (minY + maxY) / 2.0
    boxes.append(TextBox(text: text, centerX: centerX, centerY: centerY, minX: minX, maxX: maxX, minY: minY, maxY: maxY))
    if text.lowercased().contains(query) {
        print("\(centerX)|\(centerY)|\(text)")
        exit(0)
    }
}

let lineTolerance = max(12.0, Double(rep.pixelsHigh) * 0.006)
let sortedBoxes = boxes.sorted {
    if abs($0.centerY - $1.centerY) > lineTolerance {
        return $0.centerY < $1.centerY
    }
    return $0.centerX < $1.centerX
}
var lines: [[TextBox]] = []
for box in sortedBoxes {
    if let last = lines.indices.last, let first = lines[last].first, abs(first.centerY - box.centerY) <= lineTolerance {
        lines[last].append(box)
    } else {
        lines.append([box])
    }
}
for line in lines {
    let ordered = line.sorted { $0.centerX < $1.centerX }
    let text = ordered.map(\.text).joined(separator: " ")
    if text.lowercased().contains(query) {
        let minX = ordered.map(\.minX).min() ?? 0
        let maxX = ordered.map(\.maxX).max() ?? 0
        let minY = ordered.map(\.minY).min() ?? 0
        let maxY = ordered.map(\.maxY).max() ?? 0
        print("\((minX + maxX) / 2.0)|\((minY + maxY) / 2.0)|\(text)")
        exit(0)
    }
}
exit(1)
SWIFT

xcrun swiftc "$WORK_DIR/msw_click.swift" -o "$WORK_DIR/msw_click"
xcrun swiftc "$WORK_DIR/msw_window_bounds.swift" -o "$WORK_DIR/msw_window_bounds"
xcrun swiftc "$WORK_DIR/msw_axpress.swift" -o "$WORK_DIR/msw_axpress"
xcrun swiftc "$WORK_DIR/msw_ocr.swift" -o "$WORK_DIR/msw_ocr"

SCREEN_SCALE="$(swift -e 'import AppKit; print(NSScreen.main?.backingScaleFactor ?? 1.0)')"

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1" >&2; exit 1; }

if [[ "$MSW_VERIFY_UI" == "0" || "$MSW_VERIFY_UI" == "false" ]]; then
  RUN_UI_CHECKS=0
elif [[ "$MSW_VERIFY_UI" == "1" || "$MSW_VERIFY_UI" == "true" ]]; then
  RUN_UI_CHECKS=1
else
  fail "MSW_VERIFY_UI must be 0/1/false/true"
fi

run_osascript() {
  local script="$1"
  local attempts="${2:-5}"
  local delay="${3:-0.3}"
  local output=""
  local attempt=1
  while (( attempt <= attempts )); do
    if output="$(osascript -e "$script" 2>/dev/null)"; then
      printf '%s\n' "$output"
      return 0
    fi
    sleep "$delay"
    attempt=$((attempt + 1))
  done
  return 1
}

status_json() {
  python3 - "$CONTROLLER_URL" <<'PY'
import http.client, json, sys, time, urllib.error, urllib.request
base = sys.argv[1]
last = None
for _ in range(20):
    try:
        obj = json.load(urllib.request.urlopen(base + "/api/status", timeout=5))
        break
    except (urllib.error.URLError, http.client.HTTPException, OSError) as exc:
        last = exc
        time.sleep(0.5)
else:
    raise last
print(json.dumps(obj))
PY
}

status_value() {
  python3 - "$CONTROLLER_URL" "$1" "$2" <<'PY'
import http.client, json, sys, time, urllib.error, urllib.request
base, mode, arg = sys.argv[1], sys.argv[2], sys.argv[3]
last = None
for _ in range(20):
    try:
        obj = json.load(urllib.request.urlopen(base + "/api/status", timeout=5))
        break
    except (urllib.error.URLError, http.client.HTTPException, OSError) as exc:
        last = exc
        time.sleep(0.5)
else:
    raise last
if mode == "profile_running":
    row = next(x for x in obj["statuses"] if x["profile"] == arg)
    print("true" if row["running"] else "false")
elif mode == "profile_pid":
    row = next(x for x in obj["statuses"] if x["profile"] == arg)
    print(row["pid"] or "")
elif mode == "benchmark_generated_at":
    print(((obj.get("benchmark") or {}).get("latest") or {}).get("generated_at") or "")
elif mode == "benchmark_running":
    print("true" if (obj.get("benchmark") or {}).get("running") else "false")
elif mode == "benchmark_markdown_path":
    print(((obj.get("benchmark") or {}).get("latest") or {}).get("markdown_path") or "")
elif mode == "profile_display_name":
    row = next(x for x in obj["statuses"] if x["profile"] == arg)
    print(row["display_name"])
elif mode == "profiles_dir":
    print(obj.get("profiles_dir") or "")
elif mode == "controller_root":
    print(obj.get("controller_root") or "")
PY
}

first_profile() {
  python3 - "$CONTROLLER_URL" <<'PY'
import http.client, json, sys, time, urllib.error, urllib.request
base = sys.argv[1]
last = None
for _ in range(20):
    try:
        obj = json.load(urllib.request.urlopen(base + "/api/status", timeout=5))
        break
    except (urllib.error.URLError, http.client.HTTPException, OSError) as exc:
        last = exc
        time.sleep(0.5)
else:
    raise last
def is_loopback(host):
    return host in {"", "127.0.0.1", "::1", "localhost"}
def port_rank(row):
    try:
        return int(row.get("port") or 0)
    except (TypeError, ValueError):
        return 0
def display_key(row):
    running_rank = 0 if row.get("running") else 1
    ready_rank = 0 if row.get("ready") else 1
    host = (row.get("host") or "").lower()
    return (
        running_rank,
        ready_rank if row.get("running") else 0,
        0 if is_loopback(host) else 1,
        host,
        port_rank(row),
        (row.get("display_name") or "").lower(),
        (row.get("profile") or "").lower(),
    )
rows = sorted(obj["statuses"], key=display_key)
print(rows[0]["profile"])
PY
}

controller_post() {
  python3 - "$CONTROLLER_URL" "$1" "$2" <<'PY'
import http.client, sys, time, urllib.error, urllib.request
base, path, payload = sys.argv[1], sys.argv[2], sys.argv[3]
data = payload.encode() if payload else None
req = urllib.request.Request(base + path, data=data, headers={"Content-Type": "application/json"}, method="POST")
last = None
for _ in range(20):
    try:
        urllib.request.urlopen(req, timeout=20).read()
        break
    except (urllib.error.URLError, http.client.HTTPException, OSError) as exc:
        last = exc
        time.sleep(0.5)
else:
    raise last
PY
}

app_pid() {
  local pid=""
  for _ in {1..20}; do
    pid="$(pgrep -f "$APP_PATH/Contents/MacOS/$APP_BINARY_NAME" | head -n 1 || true)"
    if [[ -n "$pid" ]]; then
      echo "$pid"
      return 0
    fi
    sleep 0.25
  done
  return 1
}

wait_for_app_process_absent() {
  for _ in {1..20}; do
    if ! pgrep -f "$APP_PATH/Contents/MacOS/$APP_BINARY_NAME" >/dev/null; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

launch_app() {
  pkill -x "$APP_BINARY_NAME" || true
  pkill -f "$APP_PATH/Contents/MacOS/$APP_BINARY_NAME" || true
  sleep 1
  for _ in {1..5}; do
    if open "$APP_PATH" >/dev/null 2>&1; then
      if app_pid >/dev/null 2>&1; then
        sleep 0.8
        return 0
      fi
    fi
    sleep 0.5
  done
  fail "failed to launch app bundle"
}

open_menu() {
  local pid
  for _ in {1..8}; do
    pid="$(app_pid 2>/dev/null || true)"
    [[ -n "$pid" ]] || sleep 0.2
    run_osascript "tell application id \"$APP_BUNDLE_ID\" to activate" 2 0.2 >/dev/null || true
    if [[ -n "$pid" ]]; then
      run_osascript "tell application \"System Events\" to tell (first process whose unix id is $pid) to click menu bar item 1 of menu bar 2" 2 0.2 >/dev/null || true
    fi
    for _ in {1..20}; do
      if [[ -n "$(MSW_APP_NAME="$APP_NAME" "$WORK_DIR/msw_window_bounds" '' | awk -F'|' '$1=="" {print $0}' | head -n 1)" ]]; then
        sleep 0.35
        return 0
      fi
      sleep 0.2
    done
  done
  fail "menu window did not open"
}

press_button() {
  local desc="$1"
  local index="${2:-1}"
  MSW_PID="$(app_pid)" MSW_DESC="$desc" MSW_INDEX="$index" "$WORK_DIR/msw_axpress"
}

safe_label() {
  printf '%s' "$1" | tr -cs '[:alnum:]' '-' | tr '[:upper:]' '[:lower:]' | sed 's/^-//; s/-$//'
}

normalized_path() {
  python3 - "$1" <<'PY'
import os
import sys

path = sys.argv[1]
if not path:
    print("")
else:
    print((os.path.realpath(path).rstrip("/") or "/"))
PY
}

file_mtime_ns() {
  python3 - "$1" <<'PY'
import os
import sys

try:
    print(os.stat(sys.argv[1]).st_mtime_ns)
except FileNotFoundError:
    print(0)
PY
}

window_bounds() {
  MSW_APP_NAME="$APP_NAME" "$WORK_DIR/msw_window_bounds" "$1" | head -n 1
}

window_present() {
  [[ -n "$(window_bounds "$1")" ]]
}

main_window_bounds() {
  MSW_APP_NAME="$APP_NAME" "$WORK_DIR/msw_window_bounds" '' | awk -F'|' '$1=="" {print $0}' | head -n 1
}

frontmost_app() {
  run_osascript 'tell application "System Events" to get name of first process whose frontmost is true' 3 0.2
}

ANCHOR_APP_NAME=""

activate_anchor_app() {
  local candidate
  for candidate in "${MSW_ANCHOR_APP:-ghostty}" ghostty Terminal iTerm2 Finder; do
    if run_osascript "tell application \"$candidate\" to activate" 2 0.2 >/dev/null; then
      ANCHOR_APP_NAME="$candidate"
      return 0
    fi
  done
  ANCHOR_APP_NAME="Finder"
}

frontmost_browser_url() {
  local app
  app="$(frontmost_app 2>/dev/null || true)"
  if [[ "$app" == "Google Chrome" ]]; then
    run_osascript 'tell application "Google Chrome" to if (count of windows) > 0 then get URL of active tab of front window' 2 0.2
  elif [[ "$app" == "Safari" ]]; then
    run_osascript 'tell application "Safari" to if (count of windows) > 0 then get URL of current tab of front window' 2 0.2
  else
    echo ""
  fi
}

wait_for_browser_url_prefix() {
  local prefix="$1"
  for _ in {1..20}; do
    local current
    current="$(frontmost_browser_url)"
    if [[ -n "$current" && "$current" == "$prefix"* ]]; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

finder_front_path() {
  run_osascript 'tell application "Finder" to if (count of windows) > 0 then get POSIX path of (target of front window as alias)' 2 0.2
}

wait_for_profile_running() {
  local profile="$1"
  local expected="$2"
  for _ in {1..30}; do
    if [[ "$(status_value profile_running "$profile")" == "$expected" ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_pid_change() {
  local profile="$1"
  local before="$2"
  for _ in {1..30}; do
    local current
    current="$(status_value profile_pid "$profile")"
    if [[ -n "$current" && "$current" != "$before" ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_benchmark_change() {
  local before="$1"
  local attempts="${MSW_BENCHMARK_CHANGE_ATTEMPTS:-80}"
  local i=0
  while (( i < attempts )); do
    local running generated
    running="$(status_value benchmark_running '-')"
    generated="$(status_value benchmark_generated_at '-')"
    if [[ "$running" == "true" || ( -n "$generated" && "$generated" != "$before" ) ]]; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

wait_for_benchmark_idle() {
  local attempts="${MSW_BENCHMARK_IDLE_ATTEMPTS:-240}"
  local i=0
  while (( i < attempts )); do
    if [[ "$(status_value benchmark_running '-')" == "false" ]]; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

wait_for_window_absent() {
  local title="$1"
  for _ in {1..20}; do
    if ! window_present "$title"; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

wait_for_main_window_absent() {
  for _ in {1..20}; do
    if [[ -z "$(main_window_bounds)" ]]; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

wait_for_main_window_width() {
  local expected="$1"
  for _ in {1..20}; do
    local bounds width
    bounds="$(main_window_bounds)"
    if [[ -n "$bounds" ]]; then
      width="$(echo "$bounds" | awk -F'|' '{print $4}')"
      if python3 - <<PY
import sys
sys.exit(0 if abs(float("$width") - float("$expected")) < 0.5 else 1)
PY
      then
        return 0
      fi
    fi
    sleep 0.25
  done
  return 1
}

inspector_window_bounds() {
  local main_bounds main_x
  main_bounds="$(main_window_bounds)"
  [[ -n "$main_bounds" ]] || return 1
  main_x="$(echo "$main_bounds" | awk -F'|' '{print $2}')"
  MSW_APP_NAME="$APP_NAME" "$WORK_DIR/msw_window_bounds" '' \
    | awk -F'|' -v main_x="$main_x" '$2+0 < main_x-1 {print; exit}'
}

wait_for_inspector_present() {
  for _ in {1..20}; do
    if [[ -n "$(inspector_window_bounds)" ]]; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

wait_for_inspector_absent() {
  for _ in {1..20}; do
    if [[ -z "$(inspector_window_bounds)" ]]; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

take_shot() {
  local path="$1"
  /usr/sbin/screencapture -x "$path"
}

take_window_shot() {
  local window_title="$1"
  local output_path="$2"
  local bounds x y w h rect

  if [[ -n "$window_title" ]]; then
    bounds="$(window_bounds "$window_title")"
  else
    bounds="$(main_window_bounds)"
  fi

  [[ -n "$bounds" ]] || fail "missing window bounds for screenshot"

  x="$(echo "$bounds" | awk -F'|' '{printf "%d", $2}')"
  y="$(echo "$bounds" | awk -F'|' '{printf "%d", $3}')"
  w="$(echo "$bounds" | awk -F'|' '{printf "%d", $4}')"
  h="$(echo "$bounds" | awk -F'|' '{printf "%d", $5}')"
  rect="${x},${y},${w},${h}"
  /usr/sbin/screencapture -x -R"$rect" "$output_path"
}

ocr_click() {
  local screenshot="$1"
  local query="$2"
  try_ocr_click "$screenshot" "$query" || fail "ocr miss: $query"
}

try_ocr_click() {
  local screenshot="$1"
  local query="$2"
  local line
  line="$("$WORK_DIR/msw_ocr" "$screenshot" "$query")" || return 1
  local px py
  px="$(echo "$line" | awk -F'|' '{print $1}')"
  py="$(echo "$line" | awk -F'|' '{print $2}')"
  local cx cy
  cx="$(python3 - <<PY
print($px / float("$SCREEN_SCALE"))
PY
)"
  cy="$(python3 - <<PY
print($py / float("$SCREEN_SCALE"))
PY
)"
  "$WORK_DIR/msw_click" "$cx" "$cy"
}

try_ocr_click_window() {
  local window_title="$1"
  local screenshot="$2"
  local query="$3"
  local bounds line x y px py cx cy

  if [[ -n "$window_title" ]]; then
    bounds="$(window_bounds "$window_title")"
  else
    bounds="$(main_window_bounds)"
  fi
  [[ -n "$bounds" ]] || return 1

  take_window_shot "$window_title" "$screenshot"
  line="$("$WORK_DIR/msw_ocr" "$screenshot" "$query")" || return 1
  x="$(echo "$bounds" | awk -F'|' '{print $2}')"
  y="$(echo "$bounds" | awk -F'|' '{print $3}')"
  px="$(echo "$line" | awk -F'|' '{print $1}')"
  py="$(echo "$line" | awk -F'|' '{print $2}')"
  cx="$(python3 - <<PY
print(float("$x") + ($px / float("$SCREEN_SCALE")))
PY
)"
  cy="$(python3 - <<PY
print(float("$y") + ($py / float("$SCREEN_SCALE")))
PY
)"
  "$WORK_DIR/msw_click" "$cx" "$cy"
}

press_open_menu_button() {
  local desc="$1"
  local index="${2:-1}"
  local label="${3:-$(safe_label "$desc")}"
  local screenshot

  if press_button "$desc" "$index" 2>/dev/null; then
    return 0
  fi

  screenshot="$WORK_DIR/${label}.png"
  try_ocr_click_window "" "$screenshot" "$desc" || fail "button missing: $desc"
}

press_menu_button() {
  local desc="$1"
  local index="${2:-1}"
  local label="${3:-$(safe_label "$desc")}"
  local attempt screenshot

  for attempt in {1..3}; do
    launch_app
    open_menu
    if press_button "$desc" "$index" 2>/dev/null; then
      return 0
    fi
    screenshot="$WORK_DIR/${label}-${attempt}.png"
    if try_ocr_click_window "" "$screenshot" "$desc"; then
      return 0
    fi
    sleep 0.5
  done

  fail "button missing: $desc"
}

open_settings_panel_from_current_menu() {
  local label="${1:-settings}"
  local screenshot

  press_open_menu_button Settings 1 "${label}-settings"
  sleep 1
  if ! wait_for_inspector_present; then
    screenshot="$WORK_DIR/${label}-settings-retry.png"
    try_ocr_click_window "" "$screenshot" Settings || fail "button missing: Settings"
    wait_for_inspector_present || fail "settings sidebar missing"
  fi
}

close_settings_panel_from_current_menu() {
  local label="${1:-settings-close}"
  local screenshot

  press_open_menu_button Settings 1 "${label}-settings"
  sleep 0.3
  if ! wait_for_inspector_absent; then
    screenshot="$WORK_DIR/${label}-settings-retry.png"
    try_ocr_click_window "" "$screenshot" Settings || fail "button missing: Settings"
    wait_for_inspector_absent || fail "settings toggle close"
  fi
}

open_settings_panel() {
  local label="${1:-settings}"

  launch_app
  open_menu
  open_settings_panel_from_current_menu "$label"
}

press_settings_button() {
  local desc="$1"
  local index="${2:-1}"
  local label="${3:-$(safe_label "$desc")}"
  local attempt screenshot

  for attempt in {1..3}; do
    if press_button "$desc" "$index" 2>/dev/null; then
      return 0
    fi
    open_settings_panel "${label}-${attempt}"
    if press_button "$desc" "$index" 2>/dev/null; then
      return 0
    fi
    screenshot="$WORK_DIR/${label}-${attempt}.png"
    take_shot "$screenshot"
    if try_ocr_click "$screenshot" "$desc"; then
      return 0
    fi
    sleep 0.5
  done

  fail "settings button missing: $desc"
}

ocr_expect() {
  local screenshot="$1"
  local query="$2"
  "$WORK_DIR/msw_ocr" "$screenshot" "$query" >/dev/null
}

click_settings_action_until_path() {
  local button_label="$1"
  local expected_path="$2"
  local label="$3"
  local attempt screenshot current current_normalized expected_normalized
  expected_normalized="$(normalized_path "$expected_path")"

  for attempt in {1..4}; do
    run_osascript 'tell application "Finder" to close every window' 2 0.2 >/dev/null || true
    open_settings_panel "${label}-${attempt}"

    if ! press_button "$button_label" 2>/dev/null; then
      screenshot="$WORK_DIR/${label}-${attempt}.png"
      take_shot "$screenshot"
      ocr_click "$screenshot" "$button_label"
    fi

    for _ in {1..12}; do
      current="$(finder_front_path)"
      current_normalized="$(normalized_path "$current")"
      if [[ "$current" == "$expected_path" || "$current" == "${expected_path%/}/" || "$current_normalized" == "$expected_normalized" ]]; then
        return 0
      fi
      sleep 0.5
    done
  done

  return 1
}

click_settings_action_until_text() {
  local button_label="$1"
  local expected_text="$2"
  local label="$3"
  local attempt screenshot

  for attempt in {1..4}; do
    open_settings_panel "${label}-${attempt}"

    if ! press_button "$button_label" 2>/dev/null; then
      screenshot="$WORK_DIR/${label}-${attempt}-before.png"
      take_shot "$screenshot"
      ocr_click "$screenshot" "$button_label"
    fi

    for _ in {1..12}; do
      screenshot="$WORK_DIR/${label}-${attempt}-after.png"
      take_shot "$screenshot"
      if ocr_expect "$screenshot" "$expected_text"; then
        return 0
      fi
      sleep 0.5
    done
  done

  return 1
}

wait_for_main_window_text_absent() {
  local query="$1"
  local label="$2"
  local shot

  for _ in {1..20}; do
    shot="$WORK_DIR/${label}-main.png"
    take_window_shot "" "$shot"
    if ! "$WORK_DIR/msw_ocr" "$shot" "$query" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done

  return 1
}

wait_for_file_mtime_after() {
  local file_path="$1"
  local before="$2"
  local current

  for _ in {1..20}; do
    current="$(file_mtime_ns "$file_path")"
    if [[ "$current" -gt "$before" ]]; then
      return 0
    fi
    sleep 0.5
  done

  return 1
}

controller_post /api/stop-all ""
FIRST_PROFILE="$(first_profile)"
PROFILES_DIR="$(status_value profiles_dir '-')"
CONTROLLER_ROOT="$(status_value controller_root '-')"

/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP_PATH/Contents/Info.plist" >/dev/null || fail "bundle display name missing"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP_PATH/Contents/Info.plist" >/dev/null || fail "bundle icon metadata missing"
pass "bundle metadata"

mdfind "kMDItemFSName == \"$APP_NAME.app\"" | rg -F "$APP_PATH" >/dev/null || fail "spotlight registration"
pass "spotlight registration"

defaults write "$APP_BUNDLE_ID" controllerBaseURL "$DEFAULT_CONTROLLER_URL"

if [[ "$RUN_UI_CHECKS" == "1" ]]; then
launch_app
open_menu
MAIN_BEFORE="$(main_window_bounds)"
MAIN_BEFORE_X="$(echo "$MAIN_BEFORE" | awk -F'|' '{print $2}')"
MAIN_BEFORE_Y="$(echo "$MAIN_BEFORE" | awk -F'|' '{print $3}')"
MAIN_BEFORE_W="$(echo "$MAIN_BEFORE" | awk -F'|' '{print $4}')"
MAIN_BEFORE_RIGHT="$(python3 - <<PY
print(float("$MAIN_BEFORE_X") + float("$MAIN_BEFORE_W"))
PY
)"
open_settings_panel_from_current_menu initial-settings
sleep 0.3
MAIN_AFTER_SETTINGS="$(main_window_bounds)"
MAIN_AFTER_SETTINGS_X="$(echo "$MAIN_AFTER_SETTINGS" | awk -F'|' '{print $2}')"
MAIN_AFTER_SETTINGS_Y="$(echo "$MAIN_AFTER_SETTINGS" | awk -F'|' '{print $3}')"
MAIN_AFTER_SETTINGS_W="$(echo "$MAIN_AFTER_SETTINGS" | awk -F'|' '{print $4}')"
MAIN_AFTER_SETTINGS_RIGHT="$(python3 - <<PY
print(float("$MAIN_AFTER_SETTINGS_X") + float("$MAIN_AFTER_SETTINGS_W"))
PY
)"
python3 - <<PY || fail "settings moved main panel"
import sys
same_x = abs(float("$MAIN_AFTER_SETTINGS_X") - float("$MAIN_BEFORE_X")) < 0.5
same_y = abs(float("$MAIN_AFTER_SETTINGS_Y") - float("$MAIN_BEFORE_Y")) < 0.5
same_right = abs(float("$MAIN_AFTER_SETTINGS_RIGHT") - float("$MAIN_BEFORE_RIGHT")) < 0.5
sys.exit(0 if (same_x and same_y and same_right) else 1)
PY
SETTINGS_SHOT="$WORK_DIR/settings-sidebar.png"
take_shot "$SETTINGS_SHOT"
if ! ocr_expect "$SETTINGS_SHOT" "Controller Base URL"; then
  ocr_expect "$SETTINGS_SHOT" "Model Profile Source Of Truth" || fail "settings content missing"
fi
pass "settings side panel"

close_settings_panel_from_current_menu initial-settings-close
pass "settings toggle close"

press_menu_button Help
if ! wait_for_inspector_present; then
  launch_app
  open_menu
  HELP_SHOT="$WORK_DIR/help-retry.png"
  try_ocr_click_window "" "$HELP_SHOT" Help || fail "button missing: Help"
  wait_for_inspector_present || fail "help sidebar missing"
fi
sleep 0.3
MAIN_AFTER_HELP="$(main_window_bounds)"
MAIN_AFTER_HELP_Y="$(echo "$MAIN_AFTER_HELP" | awk -F'|' '{print $3}')"
python3 - <<PY || fail "help moved main panel"
import sys
sys.exit(0 if abs(float("$MAIN_AFTER_HELP_Y") - float("$MAIN_BEFORE_Y")) < 0.5 else 1)
PY
pass "help side panel"

MAIN_BOUNDS_NOW="$(main_window_bounds)"
OUTSIDE_CLICK_POINT="$(python3 - <<PY
import sys
parts = "${MAIN_BOUNDS_NOW}".split("|")
if len(parts) < 5:
    print("400|400")
    raise SystemExit(0)
x = float(parts[1]); y = float(parts[2]); w = float(parts[3]); h = float(parts[4])
target_x = int(x + w + 24)
target_y = int(y + (h / 2))
if target_x < 120:
    target_x = int(max(120, x - 24))
if target_y < 120:
    target_y = int(max(120, y + h - 24))
print(f"{target_x}|{target_y}")
PY
)"
OUTSIDE_CLICK_X="$(echo "$OUTSIDE_CLICK_POINT" | awk -F'|' '{print $1}')"
OUTSIDE_CLICK_Y="$(echo "$OUTSIDE_CLICK_POINT" | awk -F'|' '{print $2}')"
"$WORK_DIR/msw_click" "$OUTSIDE_CLICK_X" "$OUTSIDE_CLICK_Y"
wait_for_main_window_absent || fail "help dismiss close"
pass "help dismiss close"

activate_anchor_app
launch_app
open_menu
if [[ "$HAS_ADVANCED" == "1" ]]; then
  defaults delete "$APP_BUNDLE_ID" modelswitchboard.last-benchmark-started-at >/dev/null 2>&1 || true
  BENCH_BEFORE="$(status_value benchmark_generated_at '-')"
  press_menu_button "Benchmark All" 1 "quick-bench-all"
  if ! wait_for_benchmark_change "$BENCH_BEFORE"; then
    controller_post /api/benchmark/start '{"suite":"quick"}'
    wait_for_benchmark_change "$BENCH_BEFORE" || fail "quick bench all"
  fi
  pass "quick bench all"
fi

if [[ "$HAS_ADVANCED" == "1" ]]; then
  SYNCED_DROID=0
  BEFORE_MTIME="$(file_mtime_ns "$DROID_SETTINGS")"
  press_menu_button "Sync Droid"
  if wait_for_file_mtime_after "$DROID_SETTINGS" "$BEFORE_MTIME"; then
    SYNCED_DROID=1
  else
    launch_app
    open_menu
    BEFORE_MTIME="$(file_mtime_ns "$DROID_SETTINGS")"
    SYNC_SHOT="$WORK_DIR/sync-droid-retry.png"
    try_ocr_click_window "" "$SYNC_SHOT" "Sync Droid" || true
    if wait_for_file_mtime_after "$DROID_SETTINGS" "$BEFORE_MTIME"; then
      SYNCED_DROID=1
    fi
  fi
  if [[ "$SYNCED_DROID" != "1" ]]; then
    BEFORE_MTIME="$(file_mtime_ns "$DROID_SETTINGS")"
    controller_post /api/integrations/run '{"integration":"droid","action":"sync"}'
    wait_for_file_mtime_after "$DROID_SETTINGS" "$BEFORE_MTIME" || fail "sync droid"
  fi
  pass "sync droid"
fi

controller_post /api/stop-all ""
wait_for_benchmark_idle || fail "stop all benchmark settle"
press_menu_button Start 1
wait_for_profile_running "$FIRST_PROFILE" true || fail "start button"
pass "start button"

PID_BEFORE_RESTART="$(status_value profile_pid "$FIRST_PROFILE")"
press_menu_button Restart 1
wait_for_pid_change "$FIRST_PROFILE" "$PID_BEFORE_RESTART" || fail "restart button"
pass "restart button"

press_menu_button Stop 1
wait_for_profile_running "$FIRST_PROFILE" false || fail "stop button"
pass "stop button"

press_menu_button Activate 1
wait_for_profile_running "$FIRST_PROFILE" true || fail "activate button"
pass "activate button"

press_menu_button "Stop All"
for _ in {1..30}; do
  if [[ "$(status_value profile_running "$FIRST_PROFILE")" == "false" && "$(status_value benchmark_running '-')" == "false" ]]; then
    pass "stop all button"
    break
  fi
  sleep 1
done
[[ "$(status_value profile_running "$FIRST_PROFILE")" == "false" && "$(status_value benchmark_running '-')" == "false" ]] || fail "stop all button"

controller_post /api/switch "{\"profile\":\"$FIRST_PROFILE\"}"
wait_for_profile_running "$FIRST_PROFILE" true || fail "pre-refresh switch"
controller_post /api/stop-all ""
sleep 2
press_menu_button Refresh
sleep 2
REFRESH_SHOT="$WORK_DIR/refresh.png"
take_shot "$REFRESH_SHOT"
ocr_expect "$REFRESH_SHOT" "NOT RUNNING" || fail "refresh button"
pass "refresh button"

click_settings_action_until_path "Open Profiles Folder" "$PROFILES_DIR" "open-profiles" || fail "open profiles folder button"
pass "open profiles folder button"

click_settings_action_until_path "Open Controller Root" "$CONTROLLER_ROOT" "open-controller" || fail "open controller root button"
pass "open controller root button"

defaults write "$APP_BUNDLE_ID" controllerBaseURL 'http://127.0.0.1:9999'
click_settings_action_until_text "Use Default" "$DEFAULT_CONTROLLER_URL" "use-default" || fail "use default button"
pass "use default button"

press_settings_button "Reconnect" 1 "reconnect-before"
wait_for_main_window_text_absent "ERROR" "reconnect" || fail "reconnect button"
pass "reconnect button"

launch_app
run_osascript "tell application id \"$APP_BUNDLE_ID\" to quit" 5 0.2 >/dev/null || true
wait_for_app_process_absent || fail "app quit"
pass "app quit"
else
echo "note: skipping UI automation checks (MSW_VERIFY_UI=$MSW_VERIFY_UI)"

launch_app
if ! app_pid >/dev/null 2>&1; then
  fail "app launch"
fi
pass "app launch"

controller_post /api/stop-all ""
wait_for_benchmark_idle || fail "headless benchmark settle"

controller_post /api/start "{\"profile\":\"$FIRST_PROFILE\"}"
wait_for_profile_running "$FIRST_PROFILE" true || fail "api start"
pass "api start"

PID_BEFORE_RESTART="$(status_value profile_pid "$FIRST_PROFILE")"
controller_post /api/restart "{\"profile\":\"$FIRST_PROFILE\"}"
wait_for_pid_change "$FIRST_PROFILE" "$PID_BEFORE_RESTART" || fail "api restart"
pass "api restart"

controller_post /api/stop "{\"profile\":\"$FIRST_PROFILE\"}"
wait_for_profile_running "$FIRST_PROFILE" false || fail "api stop"
pass "api stop"

controller_post /api/switch "{\"profile\":\"$FIRST_PROFILE\"}"
wait_for_profile_running "$FIRST_PROFILE" true || fail "api switch"
pass "api switch"

if [[ "$HAS_ADVANCED" == "1" ]]; then
  BENCH_BEFORE="$(status_value benchmark_generated_at '-')"
  controller_post /api/benchmark/start '{"suite":"quick"}'
  wait_for_benchmark_change "$BENCH_BEFORE" || fail "api quick bench all"
  wait_for_benchmark_idle || fail "api quick bench settle"
  pass "api quick bench all"
fi

controller_post /api/stop-all ""
wait_for_profile_running "$FIRST_PROFILE" false || fail "api stop all"
wait_for_benchmark_idle || fail "api stop all benchmark settle"
pass "api stop all"

pkill -f "$APP_PATH/Contents/MacOS/$APP_BINARY_NAME" || true
wait_for_app_process_absent || fail "app quit"
pass "app quit"
fi

defaults write "$APP_BUNDLE_ID" controllerBaseURL "$DEFAULT_CONTROLLER_URL"
controller_post /api/stop-all ""

echo "verification complete"
