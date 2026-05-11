#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=qv/scripts/waybar/prayer-data.sh
source "$SCRIPT_DIR/prayer-data.sh"

text="$(date '+%I:%M')"
tooltip="$(
  if qvos_prayer_fetch; then
    hijri_line="$(qvos_prayer_hijri_line)"
    if [[ -n "$hijri_line" ]]; then
      printf '<b>%s</b>\n' "$hijri_line"
    fi
  fi
  printf '%s\n' "$(date '+%d %A %B %Y')"
)"

jq -cn --arg text "$text" --arg tooltip "$tooltip" \
  '{text: $text, tooltip: $tooltip}'
