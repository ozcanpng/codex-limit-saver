#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Submit one "hello" prompt for each anchored five-hour interval.
set -u -o pipefail

app_name=codex-limit-saver
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/$app_name"
config_file="${XDG_CONFIG_HOME:-$HOME/.config}/$app_name/config.env"
log_file="$state_dir/$app_name.log"

if [[ ! -r "$config_file" ]]; then
  echo "$app_name: missing configuration: $config_file" >&2
  exit 1
fi

# This file is created with mode 600 by install.sh and contains only paths and
# scheduling data; it never contains API keys or Codex credentials.
# shellcheck source=/dev/null
source "$config_file"

export HOME
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
export TZ="$TIMEZONE"
export PATH="$(dirname "$CODEX_BIN"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
umask 077
mkdir -p "$state_dir"

state_file="$state_dir/last-slot"
now_epoch="$(date +%s)"

if (( now_epoch < ANCHOR_EPOCH )); then
  exit 0
fi

current_slot=$(( (now_epoch - ANCHOR_EPOCH) / INTERVAL_SECONDS ))

if [[ "${1:-}" == "--initialize" ]]; then
  # Do not retrospectively send prompts for slots before installation.
  printf '%s\n' "$current_slot" > "$state_file"
  exit 0
fi

last_slot=-1
if [[ -r "$state_file" ]]; then
  read -r last_slot < "$state_file" || last_slot=-1
fi

if (( current_slot <= last_slot )); then
  exit 0
fi

scheduled_epoch=$(( ANCHOR_EPOCH + current_slot * INTERVAL_SECONDS ))
scheduled_time="$(date -d "@$scheduled_epoch" '+%F %T %Z')"

# Mark the interval before calling Codex so a failing invocation is logged once
# rather than retried every minute. A later interval remains unaffected.
printf '%s\n' "$current_slot" > "$state_file"
{
  printf '\n===== run_started=%s scheduled_slot=%s =====\n' "$(date '+%F %T %Z')" "$scheduled_time"
  "$CODEX_BIN" exec --ephemeral --skip-git-repo-check --sandbox read-only --color never hello
  status=$?
  printf '===== run_finished=%s exit_status=%s =====\n' "$(date '+%F %T %Z')" "$status"
  exit "$status"
} >> "$log_file" 2>&1
