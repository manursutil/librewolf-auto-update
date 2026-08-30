#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

missing=0

check_command() {
  command_name="$1"
  description="$2"

  if command -v "$command_name" >/dev/null 2>&1; then
    return
  fi

  echo "Missing dependency: $description ($command_name)" >&2
  missing=1
}

check_command bash "Bash"
check_command curl "curl"

if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  echo "Missing dependency: install either jq or Python 3" >&2
  missing=1
fi

if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "Missing dependency: install sha256sum or shasum" >&2
  missing=1
fi

if [ "$missing" -ne 0 ]; then
  exit 1
fi

mkdir -p "$HOME/.local/bin"
ln -sfn "$PWD/update-librewolf.sh" "$HOME/.local/bin/update-librewolf"
echo "==> Linked update-librewolf -> $HOME/.local/bin/update-librewolf"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *)
    echo "Note: ~/.local/bin is not currently on PATH."
    echo 'Add this to your shell config: export PATH="$HOME/.local/bin:$PATH"'
    ;;
esac

echo "✓ LibreWolf updater setup complete."
echo "Run 'update-librewolf --check' to check for updates."
