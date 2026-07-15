#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly RELEASE_API="${LIBREWOLF_RELEASE_API:-https://codeberg.org/api/v1/repos/librewolf/bsys6/releases/latest}"
readonly DOWNLOAD_ROOT="${LIBREWOLF_DOWNLOAD_ROOT:-https://dl.librewolf.net/librewolf}"

CHECK_ONLY=false
TEMP_DIR=""
MOUNT_POINT=""

usage() {
  cat <<'EOF'
Usage: update-librewolf.sh [--check]

Checks the latest LibreWolf bsys6 release and installs it when it is newer.

Options:
  --check   Only report whether an update is available.
  -h        Show this help.

Environment:
  LIBREWOLF_APP          macOS application path (default: /Applications/LibreWolf.app)
  LIBREWOLF_RELEASE_API  Override the Codeberg release API URL.
  LIBREWOLF_DOWNLOAD_ROOT Override the release download root.
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

extract_release_tag() {
  if command -v jq >/dev/null 2>&1; then
    jq --exit-status --raw-output \
      'if (.tag_name | type) == "string" then .tag_name else error("missing tag_name") end'
  elif command -v python3 >/dev/null 2>&1; then
    python3 "$SCRIPT_DIR/lib/extract_release_tag.py"
  else
    die 'Parsing Codeberg metadata requires jq or python3.'
  fi
}

extract_version() {
  grep -Eo '[0-9]+([.-][0-9]+)+' | sed -n '1p' || true
}

is_newer_version() {
  awk -v candidate="$1" -v current="$2" '
    BEGIN {
      candidate_count = split(candidate, candidate_parts, /[.-]/)
      current_count = split(current, current_parts, /[.-]/)
      count = candidate_count > current_count ? candidate_count : current_count

      for (i = 1; i <= count; i++) {
        candidate_part = i <= candidate_count ? candidate_parts[i] + 0 : 0
        current_part = i <= current_count ? current_parts[i] + 0 : 0
        if (candidate_part > current_part) exit 0
        if (candidate_part < current_part) exit 1
      }
      exit 1
    }
  '
}

normalized_architecture() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'x86_64\n' ;;
    arm64|aarch64) printf 'arm64\n' ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
}

current_version() {
  local version_output=""
  local app_path="${LIBREWOLF_APP:-/Applications/LibreWolf.app}"

  if [[ -n "${LIBREWOLF_CURRENT_VERSION:-}" ]]; then
    printf '%s\n' "$LIBREWOLF_CURRENT_VERSION"
    return
  fi

  case "$(uname -s)" in
    Darwin)
      if [[ -x "$app_path/Contents/MacOS/librewolf" ]]; then
        version_output="$("$app_path/Contents/MacOS/librewolf" --version 2>/dev/null || true)"
      fi
      ;;
    Linux)
      if command -v librewolf >/dev/null 2>&1; then
        version_output="$(librewolf --version 2>/dev/null || true)"
      elif command -v dpkg-query >/dev/null 2>&1 && dpkg-query -W librewolf >/dev/null 2>&1; then
        version_output="$(dpkg-query -W -f='${Version}' librewolf)"
      elif command -v rpm >/dev/null 2>&1 && rpm -q librewolf >/dev/null 2>&1; then
        version_output="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}' librewolf)"
      fi
      ;;
  esac

  printf '%s\n' "$version_output" | extract_version
}

select_asset() {
  local release="$1"
  local os="$2"
  local arch="$3"

  case "$os" in
    Darwin)
      printf 'librewolf-%s-macos-%s-package.dmg\n' "$release" "$arch"
      ;;
    Linux)
      if command -v dpkg >/dev/null 2>&1; then
        printf 'librewolf-%s-linux-%s-deb.deb\n' "$release" "$arch"
      elif command -v rpm >/dev/null 2>&1; then
        printf 'librewolf-%s-linux-%s-rpm.rpm\n' "$release" "$arch"
      else
        die 'Linux installation requires dpkg/apt-get or rpm/dnf.'
      fi
      ;;
    *)
      die "Unsupported operating system: $os"
      ;;
  esac
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die 'Neither sha256sum nor shasum is installed.'
  fi
}

verify_checksum() {
  local package="$1"
  local checksum_file="$2"
  local expected actual

  expected="$(awk 'NR == 1 {print $1}' "$checksum_file")"
  [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || die 'The published checksum is invalid.'
  actual="$(sha256_file "$package")"
  [[ "$actual" == "$expected" ]] || die "Checksum mismatch for $(basename "$package")"
}

run_privileged() {
  if [[ "$EUID" -eq 0 ]]; then
    "$@"
  else
    require_command sudo
    sudo "$@"
  fi
}

install_macos() {
  local package="$1"
  local app_path="${LIBREWOLF_APP:-/Applications/LibreWolf.app}"
  local source_app stage_app backup_app

  require_command hdiutil
  require_command ditto

  shopt -s nullglob
  local stale
  for stale in "${app_path}".new.* "${app_path}".old.*; do
    run_privileged rm -rf "$stale"
  done
  shopt -u nullglob

  MOUNT_POINT="$TEMP_DIR/mount"
  mkdir -p "$MOUNT_POINT"
  hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$package" >/dev/null

  source_app="$MOUNT_POINT/LibreWolf.app"
  [[ -d "$source_app" ]] || die 'LibreWolf.app was not found in the downloaded disk image.'

  stage_app="${app_path}.new.$$"
  backup_app="${app_path}.old.$$"
  run_privileged ditto "$source_app" "$stage_app"

  if [[ -e "$app_path" ]]; then
    run_privileged mv "$app_path" "$backup_app"
  fi

  if ! run_privileged mv "$stage_app" "$app_path"; then
    [[ -e "$backup_app" ]] && run_privileged mv "$backup_app" "$app_path"
    die 'Could not replace LibreWolf.app; the previous installation was restored.'
  fi

  [[ ! -e "$backup_app" ]] || run_privileged rm -rf "$backup_app"
}

install_linux() {
  local package="$1"

  case "$package" in
    *.deb)
      require_command apt-get
      run_privileged apt-get install -y "$package"
      ;;
    *.rpm)
      if command -v dnf >/dev/null 2>&1; then
        run_privileged dnf install -y "$package"
      else
        require_command rpm
        run_privileged rpm -U "$package"
      fi
      ;;
    *) die "Unsupported Linux package: $package" ;;
  esac
}

cleanup() {
  if [[ -n "$MOUNT_POINT" ]]; then
    local attempt
    for attempt in 1 2 3 4 5; do
      mount | grep -F "on $MOUNT_POINT " >/dev/null 2>&1 || break
      hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 && break
      sleep 1
    done
  fi
  [[ -z "$TEMP_DIR" ]] || rm -rf "$TEMP_DIR"
}

main() {
  local release_json latest current os arch asset download_url package checksum_file

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) CHECK_ONLY=true ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; die "Unknown option: $1" ;;
    esac
    shift
  done

  require_command curl
  os="$(uname -s)"
  arch="$(normalized_architecture)"

  release_json="$(curl --fail --silent --show-error --location --retry 3 "$RELEASE_API")"
  latest="$(printf '%s\n' "$release_json" | extract_release_tag)"
  [[ "$latest" =~ ^[0-9]+([.-][0-9]+)+$ ]] || die 'Codeberg returned an invalid release version.'

  current="$(current_version)"
  [[ -n "$current" ]] || die 'LibreWolf is not installed, or its version could not be detected.'
  [[ "$current" =~ ^[0-9]+([.-][0-9]+)+$ ]] || die "Could not understand installed version: $current"

  printf 'Installed LibreWolf: %s\n' "$current"
  printf 'Latest LibreWolf:    %s\n' "$latest"

  if ! is_newer_version "$latest" "$current"; then
    printf 'LibreWolf is already up to date.\n'
    exit 0
  fi

  if [[ "$CHECK_ONLY" == true ]]; then
    printf 'An update is available.\n'
    exit 0
  fi

  asset="$(select_asset "$latest" "$os" "$arch")"
  download_url="$DOWNLOAD_ROOT/$latest/$asset"
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/librewolf-update.XXXXXX")"
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  package="$TEMP_DIR/$asset"
  checksum_file="$package.sha256sum"

  printf 'Downloading %s...\n' "$asset"
  if [[ -t 2 ]]; then
    curl --fail --progress-bar --show-error --location --retry 3 --output "$package" "$download_url"
  else
    curl --fail --silent --show-error --location --retry 3 --output "$package" "$download_url"
  fi
  curl --fail --silent --show-error --location --retry 3 --output "$checksum_file" "$download_url.sha256sum"
  verify_checksum "$package" "$checksum_file"
  printf 'Checksum verified. Installing LibreWolf %s...\n' "$latest"

  case "$os" in
    Darwin) install_macos "$package" ;;
    Linux) install_linux "$package" ;;
  esac

  printf 'LibreWolf %s was installed successfully.\n' "$latest"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
