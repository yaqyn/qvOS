#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_root=$(mktemp -d)
test_bin="$test_root/bin"
log="$test_root/commands.log"
brightness_state="$test_root/brightness"

cleanup() {
  [[ -d $test_root ]] && rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/omarchy-hyprland-monitor-focused" <<'SCRIPT'
#!/bin/bash
printf 'DP-1\n'
SCRIPT
install -m 0755 /dev/stdin "$test_bin/omarchy-hyprland-monitor-focused-apple" <<'SCRIPT'
#!/bin/bash
exit "${QVOS_APPLE_MONITOR_STATUS:-1}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/swayosd-client" <<'SCRIPT'
#!/bin/bash
printf 'swayosd-client' >>"$QVOS_CONTROLS_TEST_LOG"
printf '|%s' "$@" >>"$QVOS_CONTROLS_TEST_LOG"
printf '\n' >>"$QVOS_CONTROLS_TEST_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/brightnessctl" <<'SCRIPT'
#!/bin/bash
printf 'brightnessctl' >>"$QVOS_CONTROLS_TEST_LOG"
printf '|%s' "$@" >>"$QVOS_CONTROLS_TEST_LOG"
printf '\n' >>"$QVOS_CONTROLS_TEST_LOG"
if [[ $1 == --device=* ]]; then
  exit
fi
case $1 in
-d)
  shift 2
  case $1 in
  max) printf '%s\n' "${QVOS_BRIGHTNESS_MAX:-10}" ;;
  get) cat "$QVOS_BRIGHTNESS_STATE" ;;
  -m) printf 'fixture,backlight,10,%s%%\n' "$(<"$QVOS_BRIGHTNESS_STATE")" ;;
  set)
    value=${2%%%}
    printf '%s\n' "$value" >"$QVOS_BRIGHTNESS_STATE"
    ;;
  esac
  ;;
-sd) printf '0\n' >"$QVOS_BRIGHTNESS_STATE" ;;
-rd) ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/wpctl" <<'SCRIPT'
#!/bin/bash
printf 'wpctl' >>"$QVOS_CONTROLS_TEST_LOG"
printf '|%s' "$@" >>"$QVOS_CONTROLS_TEST_LOG"
printf '\n' >>"$QVOS_CONTROLS_TEST_LOG"
case $1 in
get-volume) printf 'Volume: 0.50 [MUTED]\n' ;;
status) printf ' │  21. Fixture device [vol: 0.25]\n' ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/pactl" <<'SCRIPT'
#!/bin/bash
if [[ $* == '-f json list sinks' ]]; then
  if [[ ${QVOS_MALFORMED_AUDIO:-} == "1" ]]; then
    printf '[{"name":"sink-a","description":"Broken","ports":[],"properties":{"object.id":"11"},"volume":{"front-left":{"value_percent":"50%%"}}}]\n'
    exit
  fi
  cat <<'JSON'
[
  {"name":"sink-a","description":"Built-in Audio","ports":[],"properties":{"object.id":"11","device.id":"10"},"volume":{"front-left":{"value_percent":"50%"}},"mute":false},
  {"name":"sink-b","description":"Headphones","ports":[],"properties":{"object.id":"22","device.id":"21"},"volume":{"front-left":{"value_percent":"25%"}},"mute":false}
]
JSON
elif [[ $* == 'get-default-sink' ]]; then
  printf 'sink-a\n'
else
  exit 2
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/makoctl" <<'SCRIPT'
#!/bin/bash
if [[ $1 == list ]]; then
  printf 'Notification 42: Update System\nNotification 43: Another item\n'
else
  printf 'makoctl' >>"$QVOS_CONTROLS_TEST_LOG"
  printf '|%s' "$@" >>"$QVOS_CONTROLS_TEST_LOG"
  printf '\n' >>"$QVOS_CONTROLS_TEST_LOG"
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/notify-send" <<'SCRIPT'
#!/bin/bash
printf 'notify-send' >>"$QVOS_CONTROLS_TEST_LOG"
printf '|%s' "$@" >>"$QVOS_CONTROLS_TEST_LOG"
printf '\n' >>"$QVOS_CONTROLS_TEST_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
exec "$@"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/asdcontrol" <<'SCRIPT'
#!/bin/bash
printf 'asdcontrol' >>"$QVOS_CONTROLS_TEST_LOG"
printf '|%s' "$@" >>"$QVOS_CONTROLS_TEST_LOG"
printf '\n' >>"$QVOS_CONTROLS_TEST_LOG"
if [[ $1 == "--detect" ]]; then
  printf '%s: Apple Studio Display\n' "$2"
elif [[ ${2:-} != "--" ]]; then
  printf 'BRIGHTNESS=30000\n'
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/powerprofilesctl" <<'SCRIPT'
#!/bin/bash
case $1 in
list)
  printf '  power-saver:\n* balanced:\n'
  [[ ${QVOS_POWER_HAS_PERFORMANCE:-1} == "1" ]] && printf '  performance:\n'
  ;;
set)
  printf 'powerprofilesctl|set|%s\n' "$2" >>"$QVOS_CONTROLS_TEST_LOG"
  ;;
*) exit 2 ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/udevadm-fail-once" <<'SCRIPT'
#!/bin/bash
count=0
[[ ! -f $QVOS_UDEVADM_COUNT ]] || count=$(<"$QVOS_UDEVADM_COUNT")
((count += 1))
printf '%d\n' "$count" >"$QVOS_UDEVADM_COUNT"
((count > 1))
SCRIPT

run_control() {
  QVOS_CONTROLS_TESTING=1 \
  QVOS_CONTROLS_TEST_LOG="$log" \
  QVOS_BRIGHTNESS_STATE="$brightness_state" \
  PATH="$test_bin:/usr/bin" \
    "$@"
}

"$root/qvcore/controls/check"
"$root/qvcore/power/check"
printf 'ok - control and power-profile owners are singular\n'

: >"$log"
run_control "$root/qvcore/controls/osd/brightness" 0
grep -Fqx 'swayosd-client|--monitor|DP-1|--custom-icon|display-brightness-symbolic|--custom-progress|0.01|--custom-progress-text|0%' "$log" ||
  fail "zero-brightness OSD contract"
if run_control "$root/qvcore/controls/osd/brightness" 101; then
  fail "OSD accepted brightness above 100"
fi
printf 'ok - OSD values are bounded and target the focused monitor\n'

led_root="$test_root/leds"
backlight_root="$test_root/backlight"
install -d "$led_root/fixture::kbd_backlight" "$led_root/platform::micmute" "$backlight_root/intel_backlight"
: >"$led_root/platform::micmute/brightness"
printf '4\n' >"$brightness_state"
: >"$log"
QVOS_LED_ROOT="$led_root" run_control "$root/qvcore/controls/brightness/keyboard" up
grep -Fqx 'brightnessctl|-d|fixture::kbd_backlight|set|5' "$log" ||
  fail "keyboard brightness step"
grep -Fq 'keyboard-brightness-symbolic' "$log" || fail "keyboard brightness OSD"
if QVOS_LED_ROOT="$led_root" run_control "$root/qvcore/controls/brightness/keyboard" sideways; then
  fail "keyboard brightness accepted an unknown direction"
fi

printf '4\n' >"$brightness_state"
: >"$log"
QVOS_BACKLIGHT_ROOT="$backlight_root" run_control "$root/qvcore/controls/brightness/display" +5%
grep -Fqx 'brightnessctl|-d|intel_backlight|set|5%' "$log" ||
  fail "low display brightness step"
grep -Fq 'display-brightness-symbolic' "$log" || fail "display brightness OSD"
empty_backlight="$test_root/empty-backlight"
install -d "$empty_backlight"
if QVOS_BACKLIGHT_ROOT="$empty_backlight" run_control "$root/qvcore/controls/brightness/display" +1%; then
  fail "display brightness accepted an absent backlight"
fi
printf 'ok - keyboard and display brightness fail safely against validated devices\n'

hid_root="$test_root/dev"
install -d "$hid_root/usb"
: >"$hid_root/usb/hiddev0"
: >"$log"
QVOS_HID_ROOT="$hid_root" run_control "$root/qvcore/controls/brightness/display-apple" +5%
grep -Fqx "asdcontrol|$hid_root/usb/hiddev0|--|+5%" "$log" ||
  fail "Apple display brightness mutation"
grep -Fq 'display-brightness-symbolic' "$log" || fail "Apple display brightness OSD"
printf 'ok - Apple display brightness validates detected HID devices before mutation\n'

: >"$log"
QVOS_LED_ROOT="$led_root" run_control "$root/qvcore/controls/audio/input-mute"
grep -Fqx 'wpctl|set-mute|@DEFAULT_AUDIO_SOURCE@|toggle' "$log" || fail "microphone mutation"
grep -Fqx 'brightnessctl|--device=platform::micmute|set|1' "$log" || fail "microphone LED"
grep -Fq 'Microphone muted' "$log" || fail "microphone OSD"

: >"$log"
run_control "$root/qvcore/controls/audio/output-switch"
grep -Fqx 'wpctl|set-default|22' "$log" || fail "audio output switch"
grep -Fq 'sink-volume-low-symbolic' "$log" || fail "audio output volume icon"
if QVOS_MALFORMED_AUDIO=1 run_control "$root/qvcore/controls/audio/output-switch"; then
  fail "audio output switch accepted incomplete sink telemetry"
fi
printf 'ok - audio mutations preserve state feedback and validated sink selection\n'

: >"$log"
run_control "$root/qvcore/controls/notification/dismiss" 'Update System'
grep -Fqx 'makoctl|dismiss|-n|42' "$log" || fail "notification dismissal"
run_control "$root/qvcore/controls/notification/send" '!' 'Headline' 'Line one' -u critical
grep -Fqx 'notify-send|-u|critical|!    Headline|      Line one' "$log" ||
  fail "notification argument boundaries"
printf 'ok - notifications use fixed summary matching and preserve option boundaries\n'

power_root="$test_root/power-supply"
install -d "$power_root/AC" "$power_root/BAT0"
printf 'Mains\n' >"$power_root/AC/type"
printf '1\n' >"$power_root/AC/online"
printf 'Battery\n' >"$power_root/BAT0/type"
: >"$log"
QVOS_POWER_TESTING=1 QVOS_POWER_SUPPLY_ROOT="$power_root" \
QVOS_CONTROLS_TEST_LOG="$log" PATH="$test_bin:/usr/bin" \
  "$root/qvcore/power/profiles-init"
grep -Fqx 'powerprofilesctl|set|performance' "$log" || fail "AC power profile"
printf '0\n' >"$power_root/AC/online"
QVOS_POWER_TESTING=1 QVOS_POWER_SUPPLY_ROOT="$power_root" \
QVOS_CONTROLS_TEST_LOG="$log" PATH="$test_bin:/usr/bin" \
  "$root/qvcore/power/profiles-set" autodetect
tail -n1 "$log" | grep -Fqx 'powerprofilesctl|set|balanced' || fail "battery power profile"
QVOS_POWER_TESTING=1 QVOS_POWER_SUPPLY_ROOT="$power_root" \
QVOS_POWER_HAS_PERFORMANCE=0 QVOS_CONTROLS_TEST_LOG="$log" PATH="$test_bin:/usr/bin" \
  "$root/qvcore/power/profiles-set" ac
tail -n1 "$log" | grep -Fqx 'powerprofilesctl|set|balanced' || fail "AC profile fallback"
if QVOS_POWER_TESTING=1 QVOS_POWER_SUPPLY_ROOT="$power_root" \
  QVOS_CONTROLS_TEST_LOG="$log" PATH="$test_bin:/usr/bin" \
    "$root/qvcore/power/profiles-set" impossible; then
  fail "power profile accepted an unavailable target"
fi
printf 'ok - power profiles autodetect AC safely and use explicit fallbacks\n'

rules_root="$test_root/rules"
profile_rule="$rules_root/99-power-profile.rules"
legacy_command="${root%/*}/omarchy/bin/omarchy-powerprofiles-set"
install -d "$rules_root"
printf 'SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --property=After=power-profiles-daemon.service %s"\n' \
  "$legacy_command" >"$profile_rule"
printf 'SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --property=After=power-profiles-daemon.service %s"\n' \
  "$legacy_command" >>"$profile_rule"
QVOS_POWER_TESTING=1 QVOS_POWER_PROFILE_RULE="$profile_rule" \
  "$root/qvcore/power/profile-rule" >/dev/null
grep -Fq "$root/bin/qv-powerprofiles-set" "$profile_rule" ||
  fail "native power-profile rule command"
if grep -Eq 'omarchy|--unit=' "$profile_rule"; then
  fail "native power-profile rule retained its legacy path or fixed unit"
fi
[[ $(find "$rules_root" -maxdepth 1 -name '*.qvos-backup.*' | wc -l) == "1" ]] ||
  fail "power-profile rule backup"
QVOS_POWER_TESTING=1 QVOS_POWER_PROFILE_RULE="$profile_rule" \
  "$root/qvcore/power/profile-rule" >/dev/null
[[ $(find "$rules_root" -maxdepth 1 -name '*.qvos-backup.*' | wc -l) == "1" ]] ||
  fail "idempotent power-profile rule backup"

unknown_rule="$rules_root/unknown.rules"
printf 'user-owned rule\n' >"$unknown_rule"
if QVOS_POWER_TESTING=1 QVOS_POWER_PROFILE_RULE="$unknown_rule" \
  "$root/qvcore/power/profile-rule" >/dev/null 2>&1; then
  fail "unknown power-profile rule was overwritten"
fi
[[ $(<"$unknown_rule") == "user-owned rule" ]] || fail "unknown power-profile rule preservation"

rollback_rule="$rules_root/rollback.rules"
cp -- "$profile_rule" "$rollback_rule"
sed -i "s|$root/bin/qv-powerprofiles-set|$root/bin/omarchy-powerprofiles-set|g" "$rollback_rule"
rollback_before=$(<"$rollback_rule")
udevadm_count="$test_root/udevadm-count"
if QVOS_POWER_TESTING=1 QVOS_POWER_PROFILE_RULE="$rollback_rule" \
  QVOS_UDEVADM="$test_bin/udevadm-fail-once" QVOS_UDEVADM_COUNT="$udevadm_count" \
    "$root/qvcore/power/profile-rule" >/dev/null 2>&1; then
  fail "power-profile rule hid a reload failure"
fi
[[ $(<"$rollback_rule") == "$rollback_before" ]] ||
  fail "power-profile rule reload rollback"
printf 'ok - power-profile rule installation is atomic, preservation-safe, and reversible\n'

: >"$log"
QVOS_PATH="$root" run_control "$root/bin/omarchy-swayosd-brightness" 50
grep -Fq 'custom-progress|0.50' "$log" || fail "control compatibility adapter"
"$root/bin/qv" brightness display --help | grep -Fq 'qv-brightness-display' ||
  fail "native control CLI discovery"
printf 'ok - compatibility and native CLI routes share native owners\n'
