#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_LOCAL_HOST="Adityas""-MacBook"
DEFAULT_LOCAL_USER="${MSW_PRIVACY_LOCAL_USER:-aditya}"
PERSONAL_PATTERN="${MSW_PRIVACY_PERSONAL_PATTERN:-(/Users/${DEFAULT_LOCAL_USER}|${MSW_PRIVACY_LOCAL_HOST:-$DEFAULT_LOCAL_HOST})}"
if [[ -n "${MSW_PRIVACY_SECRET_VALUE_PATTERN:-}" ]]; then
  SECRET_VALUE_PATTERN="$MSW_PRIVACY_SECRET_VALUE_PATTERN"
else
  SECRET_VALUE_PATTERN='(gh[pousr]_[A-Za-z0-9_]{20,}|hf_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY)'
fi
SOURCE_SCAN_PATTERN="(${PERSONAL_PATTERN}|${SECRET_VALUE_PATTERN})"
BUNDLE_PATH_PATTERN="${MSW_PRIVACY_BUNDLE_PATH_PATTERN:-/Users/[^[:space:][:cntrl:]]+}"
BUNDLE_SCAN_PATTERN="(${BUNDLE_PATH_PATTERN}|${PERSONAL_PATTERN}|${SECRET_VALUE_PATTERN})"
FAILURES=0

record_failure() {
  FAILURES=1
}

scan_git_tree() {
  local tmp
  local status

  cd "$ROOT_DIR"
  tmp="$(mktemp)"
  set +e
  git grep -l -I -E "$SOURCE_SCAN_PATTERN" -- . ':(exclude)dist' ':(exclude).xcodebuild' >"$tmp"
  status=$?
  set -e

  case "$status" in
    0)
      while IFS= read -r line; do
        printf '%s: matched privacy pattern\n' "$line"
      done <"$tmp"
      record_failure
      ;;
    1)
      ;;
    *)
      cat "$tmp"
      rm -f "$tmp"
      printf 'git privacy scan failed with status %s\n' "$status" >&2
      exit "$status"
      ;;
  esac
  rm -f "$tmp"
}

scan_file_contents() {
  local file="$1"
  local tmp="$2"
  local description
  local grep_status

  description="$(file -b "$file" 2>/dev/null || true)"
  if [[ "$description" == *"Mach-O"* ]]; then
    set +e
    grep -a -E -q "$BUNDLE_SCAN_PATTERN" "$file"
    grep_status=$?
    set -e

    case "$grep_status" in
      0)
        printf '%s: matched privacy pattern\n' "$file"
        record_failure
        ;;
      1)
        ;;
      *)
        printf 'grep scan failed for %s with status %s\n' "$file" "$grep_status" >&2
        exit "$grep_status"
        ;;
    esac
  else
    set +e
    grep -I -E -q "$BUNDLE_SCAN_PATTERN" "$file" 2>/dev/null
    grep_status=$?
    set -e

    case "$grep_status" in
      0)
        printf '%s: matched privacy pattern\n' "$file"
        record_failure
        ;;
      1)
        ;;
      *)
        printf 'grep scan failed for %s with status %s\n' "$file" "$grep_status" >&2
        exit "$grep_status"
        ;;
    esac
  fi
}

scan_path() {
  local path="$1"
  local tmp
  local file

  [[ -e "$path" ]] || {
    printf 'missing scan target: %s\n' "$path" >&2
    exit 1
  }

  tmp="$(mktemp)"
  if [[ -f "$path" ]]; then
    scan_file_contents "$path" "$tmp"
  else
    while IFS= read -r -d '' file; do
      scan_file_contents "$file" "$tmp"
    done < <(find "$path" -type f -print0)
  fi
  rm -f "$tmp"
}

if [[ "$#" -eq 0 ]]; then
  scan_git_tree
else
  for target in "$@"; do
    scan_path "$target"
  done
fi

if [[ "$FAILURES" -ne 0 ]]; then
  printf 'privacy_audit=failed\n' >&2
  exit 1
fi

printf 'privacy_audit=passed\n'
