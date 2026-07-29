#!/usr/bin/env bash
# Install from a checkout:
#   ./Scripts/install.sh
# Install via cache-busted one-liner:
#   curl -fsSL "https://raw.githubusercontent.com/AdityaVG13/Model-Switchboard/main/Scripts/install.sh?$(date +%s)" | bash
set -euo pipefail
shopt -s lastpipe 2>/dev/null || true
umask 022

REPO_URL="${REPO_URL:-https://github.com/AdityaVG13/Model-Switchboard.git}"
APP_VARIANT="${APP_VARIANT:-base}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
SYSTEM_APPLICATIONS_DIR="${SYSTEM_APPLICATIONS_DIR:-/Applications}"
CONFIGURATION="${CONFIGURATION:-Release}"
LSREGISTER="${LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"

QUIET=0
NO_GUM=0
FORCE_INSTALL=0
EASY_MODE=0
SKIP_OPEN=0
VERIFY_ONLY=0
INSTALL_CLI=1
INSTALL_COMPLETIONS=1
HAS_GUM=0
ROOT_DIR=""
TEMP_ROOT=""
LOCK_DIR="${TMPDIR:-/tmp}/model-switchboard-install.lock"
LOCK_ACQUIRED=0
PROXY_ARGS=()

usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Build and install Model Switchboard from source.

Options:
  --variant base|plus        Install Base or Plus (default: APP_VARIANT or base)
  --install-dir PATH         App install directory (default: ~/Applications)
  --bin-dir PATH             CLI install directory (default: ~/.local/bin)
  --configuration NAME       Xcode configuration (default: Release)
  --easy-mode                Add --bin-dir to common shell rc files if missing
  --force                    Reinstall even if an app already exists
  --skip-open                Do not launch the app after install
  --no-cli                   Do not install model-switchboardctl
  --no-completions           Do not install shell completions
  --verify                   Verify the current install and exit
  --quiet                    Print only errors
  --no-gum                   Disable gum UI even when available
  -h, --help                 Show this help

Environment:
  APP_VARIANT, INSTALL_DIR, BIN_DIR, CONFIGURATION, REPO_URL,
  HTTP_PROXY, HTTPS_PROXY
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

err() {
  if [ "$HAS_GUM" -eq 1 ] && [ "$NO_GUM" -eq 0 ]; then
    gum style --foreground 196 "ERR $*" >&2
  else
    printf '\033[0;31mERR\033[0m %s\n' "$*" >&2
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
  if [ -n "$TEMP_ROOT" ]; then
    rm -rf "$TEMP_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --variant)
        shift
        [ "$#" -gt 0 ] || die "--variant requires base or plus"
        APP_VARIANT="$1"
        ;;
      --install-dir)
        shift
        [ "$#" -gt 0 ] || die "--install-dir requires a path"
        INSTALL_DIR="$1"
        ;;
      --bin-dir)
        shift
        [ "$#" -gt 0 ] || die "--bin-dir requires a path"
        BIN_DIR="$1"
        ;;
      --configuration)
        shift
        [ "$#" -gt 0 ] || die "--configuration requires a value"
        CONFIGURATION="$1"
        ;;
      --easy-mode)
        EASY_MODE=1
        ;;
      --force)
        FORCE_INSTALL=1
        ;;
      --skip-open)
        SKIP_OPEN=1
        ;;
      --no-cli)
        INSTALL_CLI=0
        ;;
      --no-completions)
        INSTALL_COMPLETIONS=0
        ;;
      --verify)
        VERIFY_ONLY=1
        SKIP_OPEN=1
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

setup_proxy() {
  PROXY_ARGS=()
  if [ -n "${HTTPS_PROXY:-}" ]; then
    PROXY_ARGS=(--proxy "$HTTPS_PROXY")
    info "Using HTTPS proxy"
  elif [ -n "${HTTP_PROXY:-}" ]; then
    PROXY_ARGS=(--proxy "$HTTP_PROXY")
    info "Using HTTP proxy"
  fi
}

resolve_root() {
  local script_source candidate
  script_source="${BASH_SOURCE[0]:-$0}"
  if [ -f "$script_source" ]; then
    candidate="$(cd "$(dirname "$script_source")/.." && pwd)"
    if [ -x "$candidate/Scripts/build-app.sh" ]; then
      ROOT_DIR="$candidate"
      return 0
    fi
  fi
  if [ -x "$PWD/Scripts/build-app.sh" ]; then
    ROOT_DIR="$(pwd)"
    return 0
  fi
  command -v git >/dev/null 2>&1 || die "git is required when running installer outside a checkout"
  TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/model-switchboard.XXXXXX")"
  if [ "${#PROXY_ARGS[@]}" -gt 0 ]; then
    run_with_spinner "Cloning Model Switchboard" \
      git -c "http.proxy=${PROXY_ARGS[1]}" -c "https.proxy=${PROXY_ARGS[1]}" clone --depth 1 "$REPO_URL" "$TEMP_ROOT/source"
  else
    run_with_spinner "Cloning Model Switchboard" git clone --depth 1 "$REPO_URL" "$TEMP_ROOT/source"
  fi
  ROOT_DIR="$TEMP_ROOT/source"
}

setup_app_names() {
  case "$APP_VARIANT" in
    base)
      APP_NAME="Model Switchboard.app"
      LEGACY_APP_NAME="ModelSwitchboard.app"
      ;;
    plus)
      APP_NAME="Model Switchboard Plus.app"
      LEGACY_APP_NAME=""
      ;;
    *)
      die "unsupported APP_VARIANT: $APP_VARIANT"
      ;;
  esac
  DIST_APP="$ROOT_DIR/dist/$APP_NAME"
  LEGACY_DIST_APP="${LEGACY_APP_NAME:+$ROOT_DIR/dist/$LEGACY_APP_NAME}"
  INSTALL_APP="$INSTALL_DIR/$APP_NAME"
  LEGACY_INSTALL_APP="${LEGACY_APP_NAME:+$INSTALL_DIR/$LEGACY_APP_NAME}"
  SYSTEM_INSTALL_APP="$SYSTEM_APPLICATIONS_DIR/$APP_NAME"
  LEGACY_SYSTEM_INSTALL_APP="${LEGACY_APP_NAME:+$SYSTEM_APPLICATIONS_DIR/$LEGACY_APP_NAME}"
}

detect_platform() {
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64) ARCH="x86_64" ;;
    arm64|aarch64) ARCH="aarch64" ;;
  esac
  [ "$OS" = "darwin" ] || die "Model Switchboard app install is macOS-only (detected $OS/$ARCH)"
}

check_disk_space() {
  local path="$1" available
  mkdir -p "$path"
  available="$(df -Pk "$path" | awk 'NR == 2 {print $4}')"
  [ "${available:-0}" -ge 200000 ] || die "not enough free disk space in $path"
}

check_write_permissions() {
  local dir="$1" probe
  mkdir -p "$dir"
  probe="$dir/.model-switchboard-write-test.$$"
  : > "$probe" || die "directory is not writable: $dir"
  rm -f "$probe"
}

check_existing_install() {
  if [ -d "$INSTALL_APP" ]; then
    if [ "$FORCE_INSTALL" -eq 1 ]; then
      info "Existing app will be replaced: $INSTALL_APP"
    else
      warn "Existing app will be refreshed: $INSTALL_APP (use --force for explicit reinstall intent)"
    fi
  fi
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
    warn "Removing stale installer lock"
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" || die "could not acquire installer lock"
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    LOCK_ACQUIRED=1
    return 0
  fi
  die "another Model Switchboard install is running (lock: $LOCK_DIR)"
}

preflight_checks() {
  info "Running preflight checks"
  [ -x "$ROOT_DIR/Scripts/build-app.sh" ] || die "missing executable: $ROOT_DIR/Scripts/build-app.sh"
  [ -x "$ROOT_DIR/Scripts/verify-privacy.sh" ] || die "missing executable: $ROOT_DIR/Scripts/verify-privacy.sh"
  [ -f "$ROOT_DIR/VERSION" ] || die "missing VERSION file"
  command -v ditto >/dev/null 2>&1 || die "ditto is required"
  if [ "$SKIP_OPEN" -eq 0 ]; then
    command -v open >/dev/null 2>&1 || die "open is required unless --skip-open is used"
  fi
  check_disk_space "$INSTALL_DIR"
  if [ "$INSTALL_CLI" -eq 1 ]; then
    check_write_permissions "$BIN_DIR"
  fi
  check_write_permissions "$INSTALL_DIR"
  check_existing_install
  ok "Preflight passed"
}

verify_install() {
  [ -d "$INSTALL_APP" ] || die "installed app missing: $INSTALL_APP"
  [ -f "$INSTALL_APP/Contents/Info.plist" ] || die "installed app Info.plist missing"
  "$ROOT_DIR/Scripts/verify-embedded-controller.sh" "$INSTALL_APP" >/dev/null \
    || die "embedded controller verification failed for $INSTALL_APP"
  "$ROOT_DIR/Scripts/verify-privacy.sh" "$INSTALL_APP" >/dev/null
  if [ "$INSTALL_CLI" -eq 1 ]; then
    [ -x "$BIN_DIR/model-switchboardctl" ] || die "CLI missing: $BIN_DIR/model-switchboardctl"
  fi
  ok "Install verification passed"
}

install_app_bundle() {
  cd "$ROOT_DIR"
  run_with_spinner "Stopping running Model Switchboard apps" \
    pkill -f 'ModelSwitchboard(Plus)?(\.app/Contents/MacOS/ModelSwitchboard(Plus)?|App)' || true
  sleep 1 || true
  run_with_spinner "Building $APP_NAME" \
    env APP_VARIANT="$APP_VARIANT" CONFIGURATION="$CONFIGURATION" "$ROOT_DIR/Scripts/build-app.sh"
  [ -d "$DIST_APP" ] || die "build did not produce app: $DIST_APP"
  rm -rf "$INSTALL_APP"
  if [ -n "$LEGACY_DIST_APP" ]; then
    rm -rf "$LEGACY_DIST_APP" "$LEGACY_INSTALL_APP"
  fi
  run_with_spinner "Installing $APP_NAME" ditto "$DIST_APP" "$INSTALL_APP"
  if [ -w "$SYSTEM_APPLICATIONS_DIR" ]; then
    rm -rf "$SYSTEM_INSTALL_APP"
    if [ -n "$LEGACY_SYSTEM_INSTALL_APP" ]; then
      rm -rf "$LEGACY_SYSTEM_INSTALL_APP"
    fi
  fi
  xattr -dr com.apple.quarantine "$DIST_APP" >/dev/null 2>&1 || true
  xattr -dr com.apple.quarantine "$INSTALL_APP" >/dev/null 2>&1 || true
  codesign --force --deep --sign - "$DIST_APP" >/dev/null 2>&1 || true
  codesign --force --deep --sign - "$INSTALL_APP" >/dev/null 2>&1 || true
  "$ROOT_DIR/Scripts/verify-privacy.sh" "$INSTALL_APP" >/dev/null
  hide_app_extension "$DIST_APP"
  hide_app_extension "$INSTALL_APP"
  register_app
}

hide_app_extension() {
  local app="$1"
  if command -v SetFile >/dev/null 2>&1; then
    SetFile -a E "$app" >/dev/null 2>&1 || true
  else
    osascript >/dev/null 2>&1 <<APPLESCRIPT || true
tell application "Finder"
  set extension hidden of (POSIX file "$app" as alias) to true
end tell
APPLESCRIPT
  fi
}

register_app() {
  if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$INSTALL_APP" >/dev/null 2>&1 || true
  fi
  if command -v mdimport >/dev/null 2>&1; then
    mdimport -f "$INSTALL_APP" >/dev/null 2>&1 || true
  fi
}

install_cli() {
  [ "$INSTALL_CLI" -eq 1 ] || return 0
  [ -f "$ROOT_DIR/Scripts/model-switchboardctl" ] || die "missing CLI source"
  mkdir -p "$BIN_DIR"
  install -m 0755 "$ROOT_DIR/Scripts/model-switchboardctl" "$BIN_DIR/model-switchboardctl"
  ok "Installed model-switchboardctl to $BIN_DIR"
}

install_completions() {
  [ "$INSTALL_CLI" -eq 1 ] || return 0
  [ "$INSTALL_COMPLETIONS" -eq 1 ] || return 0
  local bash_target zsh_target fish_target
  bash_target="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/model-switchboardctl"
  zsh_target="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions/_model-switchboardctl"
  fish_target="${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions/model-switchboardctl.fish"
  mkdir -p "$(dirname "$bash_target")" "$(dirname "$zsh_target")" "$(dirname "$fish_target")"
  if "$BIN_DIR/model-switchboardctl" completions bash > "$bash_target" &&
     "$BIN_DIR/model-switchboardctl" completions zsh > "$zsh_target" &&
     "$BIN_DIR/model-switchboardctl" completions fish > "$fish_target"; then
    ok "Installed shell completions"
  else
    warn "Could not install shell completions"
  fi
}

maybe_add_path() {
  [ "$INSTALL_CLI" -eq 1 ] || return 0
  case ":$PATH:" in
    *:"$BIN_DIR":*) return 0 ;;
  esac
  if [ "$EASY_MODE" -eq 1 ]; then
    local rc marker line
    marker="# Model Switchboard CLI"
    line="export PATH=\"$BIN_DIR:\$PATH\""
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
      if [ -e "$rc" ] && [ -w "$rc" ] && ! grep -Fq "$line" "$rc" 2>/dev/null; then
        {
          printf '\n%s\n' "$marker"
          printf '%s\n' "$line"
        } >> "$rc"
        ok "Added $BIN_DIR to PATH in $rc"
      fi
    done
  else
    warn "Add $BIN_DIR to PATH to use model-switchboardctl"
  fi
}

print_header() {
  [ "$QUIET" -eq 1 ] && return 0
  if [ "$HAS_GUM" -eq 1 ] && [ "$NO_GUM" -eq 0 ]; then
    gum style \
      "$(gum style --foreground 42 --bold 'Model Switchboard installer')" \
      "$(gum style --foreground 245 "Variant: $APP_VARIANT")"
  else
    printf '\033[1;32mModel Switchboard installer\033[0m\n'
    printf '\033[0;90mVariant: %s\033[0m\n' "$APP_VARIANT"
  fi
}

print_summary() {
  local cli_line
  if [ "$INSTALL_CLI" -eq 1 ]; then
    cli_line="CLI: $BIN_DIR/model-switchboardctl"
  else
    cli_line="CLI: skipped"
  fi
  draw_box 42 \
    "Model Switchboard installed" \
    "App: $INSTALL_APP" \
    "$cli_line" \
    "Uninstall app: $ROOT_DIR/Scripts/uninstall.sh" \
    "Uninstall controller: $ROOT_DIR/Controller/uninstall-model-switchboard-controller.sh"
  if [ "$QUIET" -eq 0 ]; then
    printf 'installed=%s\n' "$INSTALL_APP"
    printf 'dist=%s\n' "$DIST_APP"
  fi
}

main() {
  parse_args "$@"
  setup_gum
  setup_proxy
  resolve_root
  setup_app_names
  detect_platform
  print_header
  acquire_lock
  preflight_checks
  if [ "$VERIFY_ONLY" -eq 1 ]; then
    verify_install
    return 0
  fi
  install_app_bundle
  install_cli
  install_completions
  maybe_add_path
  verify_install
  if [ "$SKIP_OPEN" -eq 0 ]; then
    run_with_spinner "Opening $APP_NAME" open -a "$INSTALL_APP"
  fi
  print_summary
}

main "$@"
