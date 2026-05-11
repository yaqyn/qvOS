#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=qv/scripts/waybar/prayer-data.sh
source "$SCRIPT_DIR/prayer-data.sh"

if ! qvos_prayer_fetch; then
  qvos_prayer_empty
  exit 0
fi

now_minutes="$((10#$(date +%H) * 60 + 10#$(date +%M)))"
window_minutes="${QVOS_PRAYER_WINDOW_MINUTES:-20}"
next_name=""
next_minutes=""
window_name=""
window_delta=""

# shellcheck disable=SC2154
for prayer in "${qvos_prayers[@]}"; do
  time_value="$(jq -r --arg prayer "$prayer" '.data.timings[$prayer] // empty' "$qvos_prayer_cache_file" | sed -E 's/ .*//')"
  [[ "$time_value" =~ ^[0-9]{2}:[0-9]{2}$ ]] || continue

  hour="${time_value%%:*}"
  minute="${time_value##*:}"
  prayer_minutes="$((10#$hour * 60 + 10#$minute))"
  delta="$((now_minutes - prayer_minutes))"

  if ((delta >= -window_minutes && delta <= window_minutes)); then
    window_name="$prayer"
    window_delta="$delta"
    break
  fi

  if ((prayer_minutes > now_minutes)); then
    next_name="$prayer"
    next_minutes="$prayer_minutes"
    break
  fi
done

if [[ -n "$window_name" ]]; then
  delta_abs="${window_delta#-}"
  delta_hours="$((delta_abs / 60))"
  delta_minutes="$((delta_abs % 60))"
  sign="+"
  if ((window_delta < 0)); then
    sign="-"
  fi
  bar_text="$(printf '%s %s%02d:%02d' "$window_name" "$sign" "$delta_hours" "$delta_minutes")"
elif [[ -z "$next_name" ]]; then
  next_name="Fajr"
  fajr="$(jq -r '.data.timings.Fajr // empty' "$qvos_prayer_cache_file" | sed -E 's/ .*//')"
  if [[ "$fajr" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
    next_minutes="$((10#${fajr%%:*} * 60 + 10#${fajr##*:} + 1440))"
  fi
fi

if [[ -z "${bar_text:-}" && -z "$next_minutes" ]]; then
  qvos_prayer_empty
  exit 0
fi

if [[ -z "${bar_text:-}" ]]; then
  remaining="$((next_minutes - now_minutes))"
  remaining_hours="$((remaining / 60))"
  remaining_minutes="$((remaining % 60))"
  bar_text="$(printf '%s %02d:%02d' "$next_name" "$remaining_hours" "$remaining_minutes")"
fi

tooltip="$(
  # shellcheck disable=SC2154
  printf '<span alpha="60%%">%s</span>\n\n' "$qvos_prayer_city"
  qvos_prayer_times_lines
)"

jq -cn --arg text "$bar_text" --arg tooltip "$tooltip" \
  '{text: $text, tooltip: $tooltip}'
