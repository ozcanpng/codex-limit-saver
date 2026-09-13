#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

app_name=codex-limit-saver
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/$app_name"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/$app_name"
lib_dir="${XDG_DATA_HOME:-$HOME/.local/share}/$app_name"
systemd_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
start_time=07:00

usage() {
  cat <<'EOF'
Usage: ./install.sh [--start HH:MM] [--timezone IANA_TIMEZONE]

Installs a persistent per-user systemd timer. The default anchor is today at
07:00 in the local timezone; subsequent Codex prompts occur every five hours.
EOF
}

timezone="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
timezone="${timezone:-${TZ:-UTC}}"
while (($#)); do
  case "$1" in
    --start) start_time="${2:?--start requires HH:MM}"; shift 2 ;;
    --timezone) timezone="${2:?--timezone requires an IANA timezone}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if ! [[ "$start_time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
  echo "--start must be in 24-hour HH:MM format" >&2
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

codex_command="$(command -v codex)"
# Keep an executable launcher. In npm installations `readlink -f` can resolve
# the launcher to codex.js, which is a JavaScript module rather than an
# executable file. A symlink is resolved only when its final target is itself
# executable.
resolved_codex="$(readlink -f "$codex_command")"
if [[ -x "$resolved_codex" ]]; then
  codex_bin="$resolved_codex"
else
  codex_bin="$codex_command"
fi
if ! "$codex_bin" --version >/dev/null; then
  echo "The discovered Codex executable cannot run: $codex_bin" >&2
  exit 1
fi

anchor_date="$(TZ="$timezone" date +%F)"
anchor_epoch="$(TZ="$timezone" date -d "$anchor_date $start_time:00" +%s)"
mkdir -p "$config_dir" "$state_dir" "$lib_dir" "$systemd_dir"
install -m 700 "$repo_dir/scripts/dispatch.sh" "$lib_dir/dispatch.sh"
install -m 644 "$repo_dir/systemd/$app_name.service" "$systemd_dir/$app_name.service"
install -m 644 "$repo_dir/systemd/$app_name.timer" "$systemd_dir/$app_name.timer"

{
  printf 'CODEX_BIN=%q\n' "$codex_bin"
  printf 'TIMEZONE=%q\n' "$timezone"
  printf 'ANCHOR_EPOCH=%q\n' "$anchor_epoch"
  printf 'INTERVAL_SECONDS=18000\n'
} > "$config_dir/config.env"
chmod 600 "$config_dir/config.env"

if (( $(date +%s) >= anchor_epoch )); then
  "$lib_dir/dispatch.sh" --initialize
fi

systemctl --user daemon-reload
systemctl --user enable --now "$app_name.timer"
loginctl enable-linger "$USER" 2>/dev/null || \
  echo "Note: could not enable lingering. The timer works while you are logged in."

echo "Installed $app_name"
echo "Codex:  $codex_bin"
echo "Anchor: $(TZ="$timezone" date -d "@$anchor_epoch" '+%F %T %Z')"
systemctl --user list-timers "$app_name.timer" --all --no-pager
