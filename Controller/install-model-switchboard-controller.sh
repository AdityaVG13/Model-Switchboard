#!/usr/bin/env bash
set -euo pipefail
shopt -s lastpipe 2>/dev/null || true
umask 022

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"
LABEL="${LABEL:-io.modelswitchboard.controller}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8877}"
LOG_DIR="${LOG_DIR:-$HOME/Library/Logs/ModelSwitchboard}"
PLIST_DIR="${PLIST_DIR:-$HOME/Library/LaunchAgents}"
UNSAFE_BIND=0
AUTH_TOKEN_FILE="${AUTH_TOKEN_FILE:-}"
QUIET=0
NO_GUM=0
FORCE_INSTALL=0
NO_START=0
VERIFY_ONLY=0
HAS_GUM=0
LOCK_DIR="${TMPDIR:-/tmp}/model-switchboard-controller-install.lock"
LOCK_ACQUIRED=0

usage() {
  cat <<'USAGE'
Usage: install-model-switchboard-controller.sh [options]

Install the reference Model Switchboard controller as a per-user launchd service.

Options:
  --root PATH       Controller checkout/root (default: this script directory)
  --host HOST       Loopback bind host for the controller (default: 127.0.0.1)
  --unsafe-bind HOST
                    Bind a non-loopback host; writes a bearer token file
  --auth-token-file PATH
                    Token file for --unsafe-bind (default: ROOT/run/controller-token)
  --port PORT       Bind port for the controller (default: 8877)
  --no-start        Write/update the LaunchAgent but do not start it
  --force           Rebuild launcher even if it is up to date
  --verify          Verify the existing install and exit
  --quiet           Print only errors
  --no-gum          Disable gum UI even when available
  -h, --help        Show this help
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

setup_gum() {
  if command -v gum >/dev/null 2>&1 && [ -t 1 ]; then
    HAS_GUM=1
  fi
}

info() {
  [ "$QUIET" -eq 1 ] && return 0
  if [ "$HAS_GUM" -eq 1 ] && [ "$NO_GUM" -eq 0 ]; then
    gum style --foreground 39 "-> $*"
  else
    printf '\033[0;34m->\033[0m %s\n' "$*"
  fi
}

ok() {
  [ "$QUIET" -eq 1 ] && return 0
  if [ "$HAS_GUM" -eq 1 ] && [ "$NO_GUM" -eq 0 ]; then
    gum style --foreground 42 "OK $*"
  else
    printf '\033[0;32mOK\033[0m %s\n' "$*"
  fi
}

warn() {
  [ "$QUIET" -eq 1 ] && return 0
  if [ "$HAS_GUM" -eq 1 ] && [ "$NO_GUM" -eq 0 ]; then
    gum style --foreground 214 "WARN $*"
  else
    printf '\033[1;33mWARN\033[0m %s\n' "$*"
  fi
}

run_with_spinner() {
  local title="$1"
  shift
  if [ "$QUIET" -eq 1 ]; then
    "$@"
  elif [ "$HAS_GUM" -eq 1 ] && [ "$NO_GUM" -eq 0 ]; then
    gum spin --spinner dot --title "$title" -- "$@"
  else
    info "$title"
    "$@"
  fi
}

draw_box() {
  [ "$QUIET" -eq 1 ] && return 0
  local color="$1"
  shift
  local lines=("$@")
  if [ "$HAS_GUM" -eq 1 ] && [ "$NO_GUM" -eq 0 ]; then
    printf '%s\n' "${lines[@]}" | gum style --border normal --border-foreground "$color" --padding "1 2"
    return 0
  fi
  local max=0 line len border
  for line in "${lines[@]}"; do
    len=${#line}
    [ "$len" -gt "$max" ] && max=$len
  done
  border="+"
  for ((i = 0; i < max + 4; i++)); do border="${border}-"; done
  border="${border}+"
  printf '%s\n' "$border"
  for line in "${lines[@]}"; do
    printf '|  %-*s  |\n' "$max" "$line"
  done
  printf '%s\n' "$border"
}

cleanup() {
  if [ "$LOCK_ACQUIRED" -eq 1 ]; then
    rm -rf "$LOCK_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root)
        shift
        [ "$#" -gt 0 ] || die "--root requires a path"
        ROOT_DIR="$1"
        ;;
      --host)
        shift
        [ "$#" -gt 0 ] || die "--host requires a value"
        HOST="$1"
        ;;
      --unsafe-bind)
        shift
        [ "$#" -gt 0 ] || die "--unsafe-bind requires a value"
        HOST="$1"
        UNSAFE_BIND=1
        ;;
      --auth-token-file)
        shift
        [ "$#" -gt 0 ] || die "--auth-token-file requires a path"
        AUTH_TOKEN_FILE="$1"
        ;;
      --port)
        shift
        [ "$#" -gt 0 ] || die "--port requires a value"
        PORT="$1"
        ;;
      --no-start)
        NO_START=1
        ;;
      --force)
        FORCE_INSTALL=1
        ;;
      --verify)
        VERIFY_ONLY=1
        NO_START=1
        ;;
      --quiet)
        QUIET=1
        ;;
      --no-gum)
        NO_GUM=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
    shift
  done
}

normalize_paths() {
  ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"
  PLIST_DST="$PLIST_DIR/${LABEL}.plist"
  LAUNCHER_SRC="$ROOT_DIR/ModelSwitchboardController.swift"
  LAUNCHER_BIN="$ROOT_DIR/bin/ModelSwitchboardController"
  TOKEN_PATH="${AUTH_TOKEN_FILE:-$ROOT_DIR/run/controller-token}"
  USER_UID="$(id -u)"
  DOMAIN="gui/${USER_UID}"
  LOG_PATH="$LOG_DIR/controller.log"
  ERR_PATH="$LOG_DIR/controller.err.log"
}

detect_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="x86_64" ;;
    arm64|aarch64) arch="aarch64" ;;
  esac
  [ "$os" = "darwin" ] || die "controller LaunchAgent install is macOS-only (detected $os/$arch)"
}

check_disk_space() {
  local path="$1" available
  mkdir -p "$path"
  available="$(df -Pk "$path" | awk 'NR == 2 {print $4}')"
  [ "${available:-0}" -ge 20000 ] || die "not enough free disk space in $path"
}

check_write_permissions() {
  local dir="$1" probe
  mkdir -p "$dir"
  probe="$dir/.model-switchboard-write-test.$$"
  : > "$probe" || die "directory is not writable: $dir"
  rm -f "$probe"
}

is_loopback_host() {
  local host
  host="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$host" in
    localhost|127.*|::1|\[::1\]) return 0 ;;
    *) return 1 ;;
  esac
}

validate_bind_security() {
  if is_loopback_host "$HOST"; then
    return 0
  fi
  [ "$UNSAFE_BIND" -eq 1 ] || die "non-loopback controller host requires --unsafe-bind: $HOST"
}

prepare_auth_token_file() {
  if is_loopback_host "$HOST"; then
    return 0
  fi
  local token token_length token_dir
  token_dir="$(dirname "$TOKEN_PATH")"
  mkdir -p "$token_dir"
  chmod 700 "$token_dir"
  if [ ! -s "$TOKEN_PATH" ]; then
    token="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
    (umask 077 && printf '%s\n' "$token" > "$TOKEN_PATH")
  fi
  chmod 600 "$TOKEN_PATH"
  token_length="$(tr -d '\r\n' < "$TOKEN_PATH" | wc -c | tr -d ' ')"
  [ "${token_length:-0}" -ge 16 ] || die "auth token file must contain at least 16 bytes: $TOKEN_PATH"
}

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    LOCK_ACQUIRED=1
    return 0
  fi
  local old_pid
  old_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [ -n "$old_pid" ] && ! kill -0 "$old_pid" 2>/dev/null; then
    warn "Removing stale controller installer lock"
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" || die "could not acquire controller installer lock"
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    LOCK_ACQUIRED=1
    return 0
  fi
  die "another controller install is running (lock: $LOCK_DIR)"
}

preflight_checks() {
  info "Running controller installer preflight"
  [ -f "$LAUNCHER_SRC" ] || die "launcher source not found: $LAUNCHER_SRC"
  command -v swiftc >/dev/null 2>&1 || die "swiftc is required"
  command -v launchctl >/dev/null 2>&1 || die "launchctl is required"
  case "$PORT" in
    ''|*[!0-9]*) die "--port must be numeric: $PORT" ;;
  esac
  [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die "--port out of range: $PORT"
  validate_bind_security
  check_disk_space "$ROOT_DIR"
  check_write_permissions "$PLIST_DIR"
  check_write_permissions "$ROOT_DIR/bin"
  prepare_auth_token_file
  mkdir -p "$LOG_DIR"
  check_write_permissions "$LOG_DIR"
  if [ -f "$PLIST_DST" ]; then
    if [ "$FORCE_INSTALL" -eq 1 ]; then
      info "Existing LaunchAgent will be replaced: $PLIST_DST"
    else
      warn "Existing LaunchAgent will be refreshed: $PLIST_DST"
    fi
  fi
  ok "Controller preflight passed"
}

build_launcher() {
  mkdir -p "$ROOT_DIR/bin"
  if [ "$FORCE_INSTALL" -eq 1 ] || [ ! -x "$LAUNCHER_BIN" ] || [ "$LAUNCHER_SRC" -nt "$LAUNCHER_BIN" ]; then
    run_with_spinner "Building controller launcher" swiftc -O -o "$LAUNCHER_BIN" "$LAUNCHER_SRC"
  else
    ok "Controller launcher is up to date"
  fi
}

write_plist() {
  local bind_flag tmp_plist
  if [ "$UNSAFE_BIND" -eq 1 ]; then
    bind_flag="--unsafe-bind"
  else
    bind_flag="--host"
  fi
  tmp_plist="$(mktemp "${TMPDIR:-/tmp}/model-switchboard-controller.XXXXXX")"
  cat >"$tmp_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${LAUNCHER_BIN}</string>
    <string>--root</string>
    <string>${ROOT_DIR}</string>
    <string>${bind_flag}</string>
    <string>${HOST}</string>
    <string>--port</string>
    <string>${PORT}</string>
$(if ! is_loopback_host "$HOST"; then printf '    <string>--auth-token-file</string>\n    <string>%s</string>\n' "$TOKEN_PATH"; fi)
  </array>
  <key>WorkingDirectory</key>
  <string>${ROOT_DIR}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${LOG_PATH}</string>
  <key>StandardErrorPath</key>
  <string>${ERR_PATH}</string>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
PLIST
  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$tmp_plist" >/dev/null
  fi
  install -m 0644 "$tmp_plist" "$PLIST_DST"
  rm -f "$tmp_plist"
}

restart_launch_agent() {
  [ "$NO_START" -eq 1 ] && {
    warn "LaunchAgent written but not started (--no-start)"
    return 0
  }
  launchctl bootout "$DOMAIN" "$PLIST_DST" >/dev/null 2>&1 || true
  run_with_spinner "Bootstrapping LaunchAgent" launchctl bootstrap "$DOMAIN" "$PLIST_DST"
  launchctl kickstart -k "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
}

verify_install() {
  [ -x "$LAUNCHER_BIN" ] || die "launcher binary missing or not executable: $LAUNCHER_BIN"
  [ -f "$PLIST_DST" ] || die "LaunchAgent plist missing: $PLIST_DST"
  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$PLIST_DST" >/dev/null
  fi
  if [ "$NO_START" -eq 0 ]; then
    launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || warn "LaunchAgent is installed but launchctl does not report it running yet"
  fi
  ok "Controller install verification passed"
}

print_header() {
  [ "$QUIET" -eq 1 ] && return 0
  if [ "$HAS_GUM" -eq 1 ] && [ "$NO_GUM" -eq 0 ]; then
    gum style \
      "$(gum style --foreground 42 --bold 'Model Switchboard controller installer')" \
      "$(gum style --foreground 245 "${HOST}:${PORT}")"
  else
    printf '\033[1;32mModel Switchboard controller installer\033[0m\n'
    printf '\033[0;90m%s:%s\033[0m\n' "$HOST" "$PORT"
  fi
}

print_summary() {
  draw_box 42 \
    "Model Switchboard controller installed" \
    "Plist: $PLIST_DST" \
    "Root: $ROOT_DIR" \
    "URL: http://${HOST}:${PORT}" \
    "Logs: $LOG_PATH" \
    "Uninstall: $ROOT_DIR/uninstall-model-switchboard-controller.sh"
  if [ "$QUIET" -eq 0 ]; then
    printf 'installed=%s\n' "$PLIST_DST"
  fi
}

main() {
  parse_args "$@"
  setup_gum
  normalize_paths
  detect_platform
  print_header
  acquire_lock
  preflight_checks
  if [ "$VERIFY_ONLY" -eq 1 ]; then
    verify_install
    return 0
  fi
  build_launcher
  write_plist
  restart_launch_agent
  verify_install
  print_summary
}

main "$@"
