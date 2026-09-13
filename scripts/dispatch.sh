#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Poll Codex's machine-readable rate-limit API and submit hello after a reset.
set -u -o pipefail

app_name=codex-limit-saver
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/$app_name"
config_file="${XDG_CONFIG_HOME:-$HOME/.config}/$app_name/config.env"
log_file="$state_dir/$app_name.log"
lib_dir="$HOME/.local/lib/$app_name"

if [[ ! -r "$config_file" ]]; then
  echo "$app_name: missing configuration: $config_file" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$config_file"

export HOME
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
export PATH="$(dirname "$CODEX_BIN"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
umask 077
mkdir -p "$state_dir"

seen_file="$state_dir/last-seen-reset"
handled_file="$state_dir/last-handled-reset"
logged_file="$state_dir/last-logged-reset"
now_epoch="$(date +%s)"

if ! resets_at="$($lib_dir/read-rate-limit.py "$CODEX_BIN" 2>>"$log_file")"; then
  printf '%s rate-limit read failed; no prompt submitted\n' "$(date '+%F %T %Z')" >> "$log_file"
  exit 1
fi
if ! [[ "$resets_at" =~ ^[0-9]+$ ]] || (( resets_at <= now_epoch )); then
  printf '%s invalid reset timestamp: %q; no prompt submitted\n' "$(date '+%F %T %Z')" "$resets_at" >> "$log_file"
  exit 1
fi

# Log each newly reported future reset exactly once, including when the
# scheduler is reinstalled while that reset is already stored as state.
last_logged=0
[[ -r "$logged_file" ]] && read -r last_logged < "$logged_file" || true
if (( resets_at != last_logged )); then
  printf '%s\n' "$resets_at" > "$logged_file"
  printf '%s reset_observed=%s hello_eligible_after=%s\n' \
    "$(date '+%F %T %Z')" \
    "$(date -d "@$resets_at" '+%F %T %Z')" \
    "$(date -d "@$((resets_at + GRACE_SECONDS))" '+%F %T %Z')" >> "$log_file"
fi

last_seen=0
last_handled=0
[[ -r "$seen_file" ]] && read -r last_seen < "$seen_file" || true
[[ -r "$handled_file" ]] && read -r last_handled < "$handled_file" || true

# First observation: record the server-provided reset and its safe send time.
if (( last_seen == 0 )); then
  printf '%s\n' "$resets_at" > "$seen_file"
  exit 0
fi

# Once the server reports a later reset, the previously observed reset passed.
# Keep the old timestamp until its entire grace period has elapsed; this avoids
# sending a prompt just seconds after a reset because of minute-boundary polls.
if (( resets_at > last_seen && last_handled < last_seen )); then
  if (( now_epoch < last_seen + GRACE_SECONDS )); then
    exit 0
  fi
  due_reset="$last_seen"
else
  if (( resets_at != last_seen )); then
    printf '%s\n' "$resets_at" > "$seen_file"
  fi
  exit 0
fi

printf '%s\n' "$resets_at" > "$seen_file"
printf '%s\n' "$due_reset" > "$handled_file"
{
  printf '\n===== run_started=%s reset_detected=%s =====\n' \
    "$(date '+%F %T %Z')" "$(date -d "@$due_reset" '+%F %T %Z')"
  "$CODEX_BIN" exec --ignore-user-config --ephemeral --skip-git-repo-check --sandbox read-only --color never hello
  status=$?
  if next_reset="$($lib_dir/read-rate-limit.py "$CODEX_BIN" 2>>"$log_file")" \
    && [[ "$next_reset" =~ ^[0-9]+$ ]] \
    && (( next_reset > $(date +%s) )); then
    printf '%s\n' "$next_reset" > "$seen_file"
    printf '%s\n' "$next_reset" > "$logged_file"
    printf 'next_reset=%s next_hello_eligible_after=%s\n' \
      "$(date -d "@$next_reset" '+%F %T %Z')" \
      "$(date -d "@$((next_reset + GRACE_SECONDS))" '+%F %T %Z')"
  else
    printf 'next_reset=unavailable; it will be retried on the next timer check\n'
  fi
  printf '===== run_finished=%s exit_status=%s =====\n' "$(date '+%F %T %Z')" "$status"
  exit "$status"
} >> "$log_file" 2>&1
