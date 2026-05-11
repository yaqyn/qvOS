#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
startup_delay="${QVOS_WAYBAR_STARTUP_DELAY:-8}"

sleep "$startup_delay"

"$SCRIPT_DIR/prayerbar.sh" >/dev/null 2>&1 || true
"$SCRIPT_DIR/clock.sh" >/dev/null 2>&1 || true

if pgrep -x waybar >/dev/null 2>&1; then
  pkill -RTMIN+11 waybar >/dev/null 2>&1 || true
  pkill -RTMIN+12 waybar >/dev/null 2>&1 || true
fi
