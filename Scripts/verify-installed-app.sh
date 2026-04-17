#!/usr/bin/env zsh
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

APP_NAME="Model Switchboard"
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
    if owner == "Model Switchboard" && (target.isEmpty || name == target) {
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

func findButtons(in element: AXUIElement, matches: inout [AXUIElement]) {
    let role = value(element, kAXRoleAttribute, as: String.self) ?? ""
    let desc = value(element, kAXDescriptionAttribute, as: String.self) ?? ""
    let title = value(element, kAXTitleAttribute, as: String.self) ?? ""
    if role == kAXButtonRole as String && (desc == targetDesc || title == targetDesc) {
        matches.append(element)
    }
    let children = value(element, kAXChildrenAttribute, as: [AXUIElement].self) ?? []
    for child in children {
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

for obs in request.results ?? [] {
    guard let candidate = obs.topCandidates(1).first else { continue }
    let text = candidate.string
    if text.lowercased().contains(query) {
        let box = obs.boundingBox
        let centerX = (box.origin.x + (box.size.width / 2.0)) * Double(rep.pixelsWide)
        let centerY = (1.0 - (box.origin.y + (box.size.height / 2.0))) * Double(rep.pixelsHigh)
        print("\(centerX)|\(centerY)|\(text)")
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

status_json() {
  python3 - "$CONTROLLER_URL" <<'PY'
import json, sys, urllib.request
base = sys.argv[1]
obj = json.load(urllib.request.urlopen(base + "/api/status"))
print(json.dumps(obj))
PY
}

status_value() {
  python3 - "$CONTROLLER_URL" "$1" "$2" <<'PY'
import json, sys, urllib.request
base, mode, arg = sys.argv[1], sys.argv[2], sys.argv[3]
obj = json.load(urllib.request.urlopen(base + "/api/status"))
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
elif mode == "profile_base_url":
    row = next(x for x in obj["statuses"] if x["profile"] == arg)
    print(row["base_url"])
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
import json, sys, urllib.request
base = sys.argv[1]
obj = json.load(urllib.request.urlopen(base + "/api/status"))
rows = sorted(obj["statuses"], key=lambda row: row["display_name"].lower())
print(rows[0]["profile"])
PY
}

controller_post() {
  python3 - "$CONTROLLER_URL" "$1" "$2" <<'PY'
import sys, urllib.request
base, path, payload = sys.argv[1], sys.argv[2], sys.argv[3]
data = payload.encode() if payload else None
req = urllib.request.Request(base + path, data=data, headers={"Content-Type": "application/json"}, method="POST")
urllib.request.urlopen(req, timeout=20).read()
PY
}

app_pid() {
  pgrep -f "$APP_PATH/Contents/MacOS/ModelSwitchboard" | head -n 1
}

launch_app() {
  pkill -f "$APP_PATH/Contents/MacOS/ModelSwitchboard" || true
  sleep 1
  open -a "$APP_PATH"
  sleep 1.5
}

open_menu() {
  osascript -e 'tell application "System Events" to tell process "ModelSwitchboard" to click menu bar item 1 of menu bar 2' >/dev/null
  for _ in {1..20}; do
    if [[ -n "$("$WORK_DIR/msw_window_bounds" '' | awk -F'|' '$1=="" {print $0}' | head -n 1)" ]]; then
      sleep 0.5
      return 0
    fi
    sleep 0.25
  done
  fail "menu window did not open"
}

press_button() {
  local desc="$1"
  local index="${2:-1}"
  MSW_PID="$(app_pid)" MSW_DESC="$desc" MSW_INDEX="$index" "$WORK_DIR/msw_axpress"
}

window_bounds() {
  "$WORK_DIR/msw_window_bounds" "$1" | head -n 1
}

main_window_bounds() {
  "$WORK_DIR/msw_window_bounds" '' | awk -F'|' '$1=="" {print $0}' | head -n 1
}

frontmost_app() {
  osascript -e 'tell application "System Events" to get name of first process whose frontmost is true'
}

frontmost_browser_url() {
  local app
  app="$(frontmost_app)"
  if [[ "$app" == "Google Chrome" ]]; then
    osascript -e 'tell application "Google Chrome" to if (count of windows) > 0 then get URL of active tab of front window'
  elif [[ "$app" == "Safari" ]]; then
    osascript -e 'tell application "Safari" to if (count of windows) > 0 then get URL of current tab of front window'
  else
    echo ""
  fi
}

finder_front_path() {
  osascript -e 'tell application "Finder" to if (count of windows) > 0 then get POSIX path of (target of front window as alias)'
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
  for _ in {1..40}; do
    local running generated
    running="$(status_value benchmark_running '-')"
    generated="$(status_value benchmark_generated_at '-')"
    if [[ "$running" == "true" || ( -n "$generated" && "$generated" != "$before" ) ]]; then
      return 0
    fi
    sleep 1
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
  local line
  line="$("$WORK_DIR/msw_ocr" "$screenshot" "$query")" || fail "ocr miss: $query"
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

ocr_expect() {
  local screenshot="$1"
  local query="$2"
  "$WORK_DIR/msw_ocr" "$screenshot" "$query" >/dev/null
}

click_settings_action_until_path() {
  local query="$1"
  local expected_path="$2"
  local label="$3"
  local attempt screenshot current

  for attempt in {1..4}; do
    osascript -e 'tell application "Finder" to close every window'
    launch_app
    open_menu
    press_button Settings
    sleep 1

    screenshot="$WORK_DIR/${label}-${attempt}.png"
    take_shot "$screenshot"
    ocr_click "$screenshot" "$query"

    for _ in {1..12}; do
      current="$(finder_front_path)"
      if [[ "$current" == "$expected_path" || "$current" == "${expected_path%/}/" ]]; then
        return 0
      fi
      sleep 0.5
    done
  done

  return 1
}

click_settings_action_until_text() {
  local button_query="$1"
  local expected_text="$2"
  local label="$3"
  local attempt screenshot

  for attempt in {1..4}; do
    launch_app
    open_menu
    press_button Settings
    sleep 1

    screenshot="$WORK_DIR/${label}-${attempt}-before.png"
    take_shot "$screenshot"
    ocr_click "$screenshot" "$button_query"

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

controller_post /api/stop-all ""
FIRST_PROFILE="$(first_profile)"
FIRST_PROFILE_BASE_URL="$(status_value profile_base_url "$FIRST_PROFILE")"
PROFILES_DIR="$(status_value profiles_dir '-')"
CONTROLLER_ROOT="$(status_value controller_root '-')"

/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP_PATH/Contents/Info.plist" >/dev/null || fail "bundle display name missing"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP_PATH/Contents/Info.plist" >/dev/null || fail "bundle icon metadata missing"
pass "bundle metadata"

mdfind "kMDItemFSName == \"$APP_NAME.app\"" | rg -F "$APP_PATH" >/dev/null || fail "spotlight registration"
pass "spotlight registration"

launch_app
open_menu
MAIN_BEFORE="$(main_window_bounds)"
press_button Settings
sleep 1
SETTINGS_BOUNDS="$(window_bounds Settings)"
MAIN_AFTER_SETTINGS="$(main_window_bounds)"
[[ -n "$SETTINGS_BOUNDS" ]] || fail "settings panel missing"
[[ "$MAIN_BEFORE" == "$MAIN_AFTER_SETTINGS" ]] || fail "settings shifted main window"
[[ "$(echo "$SETTINGS_BOUNDS" | awk -F'|' '{print $2}')" -lt "$(echo "$MAIN_BEFORE" | awk -F'|' '{print $2}')" ]] || fail "settings did not open to the side"
pass "settings side panel"

press_button Help
sleep 1
HELP_BOUNDS="$(window_bounds Help)"
MAIN_AFTER_HELP="$(main_window_bounds)"
[[ -n "$HELP_BOUNDS" ]] || fail "help panel missing"
[[ "$MAIN_BEFORE" == "$MAIN_AFTER_HELP" ]] || fail "help shifted main window"
pass "help side panel"

osascript -e 'tell application "ghostty" to activate'
launch_app
open_menu
press_button Dashboard
sleep 2
[[ "$(frontmost_browser_url)" == "$CONTROLLER_URL/" ]] || fail "dashboard button"
pass "dashboard button"

osascript -e 'tell application "ghostty" to activate'
launch_app
open_menu
press_button Open 1
sleep 2
[[ "$(frontmost_browser_url)" == "$FIRST_PROFILE_BASE_URL/models" ]] || fail "open endpoint button"
pass "open endpoint button"

osascript -e 'tell application "ghostty" to activate'
launch_app
open_menu
press_button "Latest Bench"
sleep 2
[[ "$(frontmost_app)" != "ghostty" ]] || fail "latest bench button"
pass "latest bench button"

launch_app
open_menu
press_button "Quick Bench All"
wait_for_benchmark_change "$(status_value benchmark_generated_at '-')" || fail "quick bench all"
pass "quick bench all"

launch_app
open_menu
BEFORE_MTIME="$(stat -f '%m' "$DROID_SETTINGS")"
press_button "Sync Droid"
for _ in {1..20}; do
  NOW_MTIME="$(stat -f '%m' "$DROID_SETTINGS")"
  if [[ "$NOW_MTIME" -gt "$BEFORE_MTIME" ]]; then
    pass "sync droid"
    break
  fi
  sleep 1
done
[[ "$NOW_MTIME" -gt "$BEFORE_MTIME" ]] || fail "sync droid"

controller_post /api/stop-all ""
launch_app
open_menu
press_button Start 1
wait_for_profile_running "$FIRST_PROFILE" true || fail "start button"
pass "start button"

PID_BEFORE_RESTART="$(status_value profile_pid "$FIRST_PROFILE")"
launch_app
open_menu
press_button Restart 1
wait_for_pid_change "$FIRST_PROFILE" "$PID_BEFORE_RESTART" || fail "restart button"
pass "restart button"

BENCH_BEFORE="$(status_value benchmark_generated_at '-')"
launch_app
open_menu
press_button Bench 1
wait_for_benchmark_change "$BENCH_BEFORE" || fail "profile bench button"
pass "profile bench button"

launch_app
open_menu
press_button Stop 1
wait_for_profile_running "$FIRST_PROFILE" false || fail "stop button"
pass "stop button"

launch_app
open_menu
press_button Activate 1
wait_for_profile_running "$FIRST_PROFILE" true || fail "activate button"
pass "activate button"

launch_app
open_menu
press_button "Stop All"
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
launch_app
open_menu
controller_post /api/stop-all ""
sleep 2
press_button Refresh
sleep 2
REFRESH_SHOT="$WORK_DIR/refresh.png"
take_shot "$REFRESH_SHOT"
ocr_expect "$REFRESH_SHOT" "NOT RUNNING" || fail "refresh button"
pass "refresh button"

click_settings_action_until_path "Open Profiles" "$PROFILES_DIR" "open-profiles" || fail "open profiles folder button"
pass "open profiles folder button"

click_settings_action_until_path "Open Controller" "$CONTROLLER_ROOT" "open-controller" || fail "open controller root button"
pass "open controller root button"

defaults write io.modelswitchboard.app controllerBaseURL 'http://127.0.0.1:9999'
click_settings_action_until_text "Use Default" "$DEFAULT_CONTROLLER_URL" "use-default" || fail "use default button"
pass "use default button"

RECONNECT_SHOT="$WORK_DIR/reconnect-before.png"
take_shot "$RECONNECT_SHOT"
ocr_click "$RECONNECT_SHOT" "Reconnect"
wait_for_main_window_text_absent "ERROR" "reconnect" || fail "reconnect button"
pass "reconnect button"

launch_app
open_menu
if ! press_button Quit 2>/dev/null; then
  true
fi
sleep 1
if pgrep -f "$APP_PATH/Contents/MacOS/ModelSwitchboard" >/dev/null; then
  fail "quit button"
fi
pass "quit button"

defaults write io.modelswitchboard.app controllerBaseURL "$DEFAULT_CONTROLLER_URL"
controller_post /api/stop-all ""

echo "verification complete"
