#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

timezone="${1:-$(date +%Z)}"
anchor_date="${2:-$(TZ="$timezone" date +%F)}"
anchor_epoch="$(TZ="$timezone" date -d "$anchor_date 07:00:00" +%s)"

echo "Timezone: $timezone"
echo "Anchor:   $(TZ="$timezone" date -d "@$anchor_epoch" '+%F %T %Z')"
echo
for index in $(seq 0 11); do
  epoch=$((anchor_epoch + index * 18000))
  TZ="$timezone" date -d "@$epoch" '+%F %T %Z'
done
