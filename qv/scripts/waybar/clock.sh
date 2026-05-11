#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=qv/scripts/waybar/prayer-data.sh
source "$SCRIPT_DIR/prayer-data.sh"

case "$(date +%u)" in
1) day_name="Ithnayn" ;;
2) day_name="Thulatha" ;;
3) day_name="Arbia" ;;
4) day_name="Khamis" ;;
5) day_name="Jumuah" ;;
6) day_name="Sabt" ;;
7) day_name="Ahad" ;;
esac

text="$(date "+$day_name %I:%M")"
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
