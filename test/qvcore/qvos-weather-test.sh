#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
test_bin="$test_root/bin"
request_log="$test_root/requests"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_home" "$test_bin"
: >"$request_log"
install -m 0755 /dev/stdin "$test_bin/curl" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_WEATHER_REQUEST_LOG"
[[ ${QVOS_WEATHER_CURL_STATUS:-0} == "0" ]] || exit "$QVOS_WEATHER_CURL_STATUS"
if [[ ${QVOS_WEATHER_OVERSIZE:-0} == "1" ]]; then
  head -c 1048577 /dev/zero | tr '\0' x
else
  printf '%s\n' "$QVOS_WEATHER_DATA"
fi
SCRIPT

weather_data='{
  "current_condition": [{
    "weatherCode": "113",
    "temp_C": "27",
    "winddir16Point": "NW",
    "windspeedKmph": "14"
  }],
  "weather": [{"astronomy": [{"sunrise": "06:00 AM", "sunset": "06:00 PM"}]}],
  "nearest_area": [{"areaName": [{"value": "cairo"}]}],
  "request": [{"query": "fallback"}]
}'
noon=$(date -d 'today 12:00 PM' +%s)
night=$(date -d 'today 11:00 PM' +%s)

run_weather() {
  HOME="$test_home" \
    QVOS_PATH="$root" \
    QVOS_WEATHER_DATA="${QVOS_WEATHER_DATA:-$weather_data}" \
    QVOS_WEATHER_NOW_EPOCH="${QVOS_WEATHER_NOW_EPOCH:-$noon}" \
    QVOS_WEATHER_REQUEST_LOG="$request_log" \
    PATH="$test_bin:/usr/bin" \
    "$@"
}

: >"$request_log"
status=$(run_weather "$root/bin/qv-weather-status")
[[ $status == '    Cairo · Temp 27°C · Wind NW 14 km/h' ]] ||
  fail "validated weather status formatting"
[[ $(wc -l <"$request_log") == 1 ]] || fail "status provider request count"
grep -Fq -- '--connect-timeout 2 --max-time 4 --max-filesize 1048576 https://wttr.in?format=j1' \
  "$request_log" || fail "bounded fixed weather request"

: >"$request_log"
icon=$(QVOS_WEATHER_NOW_EPOCH="$night" run_weather \
  "$root/bin/qv-weather-icon")
[[ $icon == "" ]] || fail "nighttime clear-weather icon"
[[ $(wc -l <"$request_log") == 1 ]] || fail "icon provider request count"

: >"$request_log"
compatibility=$(run_weather "$root/bin/omarchy-weather-status")
[[ $compatibility == "$status" && $(wc -l <"$request_log") == 1 ]] ||
  fail "weather compatibility adapter"
printf 'ok - weather status and icon share validated one-request parsing\n'

for failure in transport malformed schema oversized; do
  : >"$request_log"
  set +e
  case $failure in
  transport)
    output=$(QVOS_WEATHER_CURL_STATUS=7 run_weather \
      "$root/bin/qv-weather-status" 2>/dev/null)
    ;;
  malformed)
    output=$(QVOS_WEATHER_DATA='not-json' run_weather \
      "$root/bin/qv-weather-status" 2>/dev/null)
    ;;
  schema)
    output=$(QVOS_WEATHER_DATA='{}' run_weather \
      "$root/bin/qv-weather-status" 2>/dev/null)
    ;;
  oversized)
    output=$(QVOS_WEATHER_OVERSIZE=1 run_weather \
      "$root/bin/qv-weather-status" 2>/dev/null)
    ;;
  esac
  failure_status=$?
  set -e
  ((failure_status == 1)) || fail "$failure weather status"
  [[ $output == "Weather unavailable" ]] || fail "$failure weather fallback"
done

control_data=${weather_data/"cairo"/"bad\\nplace"}
if QVOS_WEATHER_DATA="$control_data" run_weather \
  "$root/bin/qv-weather-status" >/dev/null 2>&1; then
  fail "escaped control data was accepted as a location"
fi
if run_weather "$root/bin/qv-weather-icon" unexpected >/dev/null 2>&1; then
  fail "unexpected weather arguments were accepted"
fi
printf 'ok - weather failures are bounded, silent in icons, and truthful in status\n'

install -m 0755 /dev/stdin "$test_bin/qv-weather-icon" <<'SCRIPT'
#!/bin/bash
printf '%b\n' '\x22\x5c'
SCRIPT
waybar_json=$(PATH="$test_bin:/usr/bin" "$root/qvcore/weather/waybar")
jq -e '.text == "\"\\"' <<<"$waybar_json" >/dev/null ||
  fail "Waybar weather JSON escaping"
install -m 0755 /dev/stdin "$test_bin/qv-weather-icon" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
waybar_json=$(PATH="$test_bin:/usr/bin" "$root/qvcore/weather/waybar")
jq -e '.text == "" and .class == "unavailable"' <<<"$waybar_json" >/dev/null ||
  fail "Waybar weather unavailable state"
printf 'ok - Waybar consumes only the native weather icon safely\n'
