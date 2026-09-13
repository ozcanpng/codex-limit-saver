#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

app_name=codex-limit-saver
systemd_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
lib_dir="${XDG_DATA_HOME:-$HOME/.local/share}/$app_name"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/$app_name"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/$app_name"

systemctl --user disable --now "$app_name.timer" 2>/dev/null || true
rm -f "$systemd_dir/$app_name.service" "$systemd_dir/$app_name.timer"
rm -rf "$lib_dir" "$config_dir" "$state_dir"
systemctl --user daemon-reload
echo "Uninstalled $app_name"
