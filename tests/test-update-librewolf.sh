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
assert_equal "$(printf '%s' '{"body":"- Fixed startup\n- Improved privacy"}' | extract_release_notes)" $'- Fixed startup\n- Improved privacy'
assert_equal "$(printf '%s' '{"body":null}' | extract_release_notes)" ''
assert_equal "$(print_release_notes $'- Fixed startup\n- Improved privacy')" $'\nRelease notes:\n- Fixed startup\n- Improved privacy'
assert_equal "$(print_release_notes '')" ''
assert_equal "$(printf '%s' 'LibreWolf 152.0.5-1' | extract_version)" '152.0.5-1'
assert_equal "$(select_asset 152.0.5-1 Darwin arm64)" 'librewolf-152.0.5-1-macos-arm64-package.dmg'

cleanup_log="$(mktemp)"
cleanup_state="$(mktemp)"
cleanup_warning="$(mktemp)"
cleanup_root="$(mktemp -d)"
cleanup_alias="${cleanup_root}.alias"
ln -s "$cleanup_root" "$cleanup_alias"
printf 'mounted\n' >"$cleanup_state"
(
  TEMP_DIR="$cleanup_alias/librewolf-update.test"
  MOUNT_POINT="$TEMP_DIR/mount"
  mkdir -p "$MOUNT_POINT"
  physical_mount="$(cd "$MOUNT_POINT" && pwd -P)"
  mount() {
    grep -q '^mounted$' "$cleanup_state" &&
      printf 'disk image on %s (hfs, local, read-only)\n' "$physical_mount"
  }
  hdiutil() { printf 'detached\n' >"$cleanup_state"; }
  sleep() { :; }
  rm() {
    if grep -q '^mounted$' "$cleanup_state"; then
      printf 'rm called while disk image was mounted: %s\n' "$*" >>"$cleanup_log"
      return 1
    fi
    command rm "$@"
  }
  cleanup 2>"$cleanup_warning"
)
if [[ -s "$cleanup_log" || -s "$cleanup_warning" || "$(<"$cleanup_state")" != detached ]]; then
  printf 'Cleanup did not detach a mount reached through a symlinked path.\n' >&2
  command rm -rf "$cleanup_log" "$cleanup_state" "$cleanup_warning" "$cleanup_alias" "$cleanup_root"
  exit 1
fi
command rm -rf "$cleanup_log" "$cleanup_state" "$cleanup_warning" "$cleanup_alias" "$cleanup_root"

printf 'All tests passed.\n'
