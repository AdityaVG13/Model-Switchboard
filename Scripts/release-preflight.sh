#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }
note() { printf 'note: %s\n' "$1"; }

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "missing file: $path"
}

require_executable() {
  local path="$1"
  [[ -x "$path" ]] || fail "not executable: $path"
}

VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION must use x.y.z format"
pass "version format"

require_file "Scripts/sign-and-notarize-dmg.sh"
require_file "Scripts/verify-distribution.sh"
require_file "Scripts/verify-installed-app.sh"
require_file "Scripts/verify-privacy.sh"
require_file "Scripts/bump-version.py"
require_file ".github/workflows/release.yml"
require_file "README.md"
require_file "project.yml"
require_file "CHANGELOG.md"
pass "required release files"

require_executable "Scripts/build-app.sh"
require_executable "Scripts/build-dmg.sh"
require_executable "Scripts/bump-version.py"
require_executable "Scripts/check-cycles.py"
require_executable "Scripts/sign-and-notarize-dmg.sh"
require_executable "Scripts/verify-distribution.sh"
require_executable "Scripts/verify-installed-app.sh"
require_executable "Scripts/verify-privacy.sh"
pass "release scripts executable"

MARKETING_VERSION="$(awk '/MARKETING_VERSION:/ {print $2; exit}' project.yml)"
CURRENT_PROJECT_VERSION="$(awk '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)"
[[ "$MARKETING_VERSION" == "$VERSION" ]] || fail "project MARKETING_VERSION ($MARKETING_VERSION) does not match VERSION ($VERSION)"
[[ "$CURRENT_PROJECT_VERSION" == "$VERSION" ]] || fail "project CURRENT_PROJECT_VERSION ($CURRENT_PROJECT_VERSION) does not match VERSION ($VERSION)"
pass "project versions match VERSION"

grep -Fq "version-$VERSION-blue" README.md || fail "README version badge does not match VERSION"
pass "README version badge"

grep -Fq "## [$VERSION]" CHANGELOG.md || fail "CHANGELOG.md missing entry for VERSION"
pass "CHANGELOG entry"

required_secrets=(
  APPLE_CERTIFICATE_P12_BASE64
  APPLE_CERTIFICATE_PASSWORD
  APPLE_DEVELOPER_IDENTITY
  APPLE_NOTARY_API_KEY_P8_BASE64
  APPLE_NOTARY_API_KEY_ID
  APPLE_NOTARY_API_ISSUER_ID
)
for secret in "${required_secrets[@]}"; do
  grep -Fq "secrets.$secret" .github/workflows/release.yml || fail "release workflow missing secret reference: $secret"
done
pass "release workflow secret wiring"

"$ROOT_DIR/Scripts/verify-privacy.sh"
pass "privacy audit"

if [[ "${MSW_PREFLIGHT_SKIP_TESTS:-0}" != "1" ]]; then
  note "running swift test"
  swift test
  pass "swift test"

  note "running dependency cycle check"
  ./Scripts/check-cycles.py
  pass "dependency cycle check"

  note "running release automation tests"
  if command -v uv >/dev/null 2>&1; then
    uv run python3 -m unittest discover -s Scripts/tests -p 'test_*.py'
  else
    python3 -m unittest discover -s Scripts/tests -p 'test_*.py'
  fi
  pass "release automation tests"

  note "running controller unit tests"
  if command -v uv >/dev/null 2>&1; then
    uv run python3 -m unittest discover -s Controller/tests -p 'test_*.py'
  else
    python3 -m unittest discover -s Controller/tests -p 'test_*.py'
  fi
  pass "controller tests"
else
  note "skipping test suite (MSW_PREFLIGHT_SKIP_TESTS=1)"
fi

if [[ "${MSW_PREFLIGHT_SKIP_BUILDS:-0}" != "1" ]]; then
  note "building base app"
  ./Scripts/build-app.sh
  ./Scripts/verify-distribution.sh
  pass "base app build"

  note "building plus app"
  APP_VARIANT=plus ./Scripts/build-app.sh
  APP_VARIANT=plus ./Scripts/verify-distribution.sh
  pass "plus app build"
else
  note "skipping app builds (MSW_PREFLIGHT_SKIP_BUILDS=1)"
fi

printf 'release_preflight=v%s\n' "$VERSION"
