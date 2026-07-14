#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../update-librewolf.sh
source "$SCRIPT_DIR/update-librewolf.sh"

assert_success() {
  "$@" || {
    printf 'Expected success: %s\n' "$*" >&2
    exit 1
  }
}

assert_failure() {
  if "$@"; then
    printf 'Expected failure: %s\n' "$*" >&2
    exit 1
  fi
}

assert_equal() {
  if [[ "$1" != "$2" ]]; then
    printf 'Expected <%s>, got <%s>\n' "$1" "$2" >&2
    exit 1
  fi
}

assert_success is_newer_version 152.0.5-1 152.0.4-1
assert_success is_newer_version 152.0.5-2 152.0.5-1
assert_failure is_newer_version 152.0.5-1 152.0.5-1
assert_failure is_newer_version 151.0.1-1 152.0-1
assert_equal "$(printf '%s' '{"tag_name":"152.0.5-1","name":"release"}' | extract_release_tag)" '152.0.5-1'
assert_equal "$(printf '%s' '{"body":"fake \"tag_name\": \"999.0-1\"","tag_name":"152.0.5-1"}' | extract_release_tag)" '152.0.5-1'
assert_failure extract_release_tag 2>/dev/null <<<'{"name":"missing tag"}'
assert_equal "$(printf '%s' 'LibreWolf 152.0.5-1' | extract_version)" '152.0.5-1'
assert_equal "$(select_asset 152.0.5-1 Darwin arm64)" 'librewolf-152.0.5-1-macos-arm64-package.dmg'

printf 'All tests passed.\n'
