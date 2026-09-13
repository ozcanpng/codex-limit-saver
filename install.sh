#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

app_name=codex-limit-saver
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/$app_name"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/$app_name"
lib_dir="$HOME/.local/lib/$app_name"
systemd_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
grace_seconds=60

usage() {
  cat <<'EOF'
Usage: ./install.sh [--grace-seconds SECONDS]

Installs a persistent per-user systemd timer. Codex's machine-readable
rate-limit API determines the actual reset time; hello runs after that reset.
EOF
}

while (($#)); do
  case "$1" in
    --grace-seconds) grace_seconds="${2:?--grace-seconds requires seconds}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if ! [[ "$grace_seconds" =~ ^[0-9]+$ ]] || (( grace_seconds < 60 )); then
  echo "--grace-seconds must be an integer of at least 60" >&2
  exit 2
fi
if ! command -v systemctl >/dev/null || ! systemctl --user show-environment >/dev/null 2>&1; then
  echo "This installer requires a running per-user systemd manager." >&2
  echo "Use a systemd-based Linux distribution and log in graphically or with a user session." >&2
  exit 1
fi
if ! command -v codex >/dev/null; then
  echo "Codex CLI was not found in PATH. Install and authenticate Codex first." >&2
  exit 1
fi
if ! command -v python3 >/dev/null; then
  echo "Python 3 is required for safe JSON-RPC parsing." >&2
  exit 1
fi

codex_bin="$(command -v codex)"
if ! "$codex_bin" --version >/dev/null; then
  echo "The discovered Codex executable cannot run: $codex_bin" >&2
  exit 1
fi

mkdir -p "$config_dir" "$state_dir" "$lib_dir" "$systemd_dir"
install -m 700 "$repo_dir/scripts/dispatch.sh" "$lib_dir/dispatch.sh"
install -m 700 "$repo_dir/scripts/read-rate-limit.py" "$lib_dir/read-rate-limit.py"
install -m 644 "$repo_dir/systemd/$app_name.service" "$systemd_dir/$app_name.service"
install -m 644 "$repo_dir/systemd/$app_name.timer" "$systemd_dir/$app_name.timer"

{
  printf 'CODEX_BIN=%q\n' "$codex_bin"
  printf 'GRACE_SECONDS=%q\n' "$grace_seconds"
} > "$config_dir/config.env"
chmod 600 "$config_dir/config.env"

systemctl --user daemon-reload
systemctl --user enable --now "$app_name.timer"
loginctl enable-linger "$USER" 2>/dev/null || \
  echo "Note: could not enable lingering. The timer works while you are logged in."

echo "Installed $app_name"
echo "Codex:  $codex_bin"
echo "Grace:  ${grace_seconds}s after the reported reset"
systemctl --user list-timers "$app_name.timer" --all --no-pager
