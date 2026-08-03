#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
launcher="$root/qvcore/screensaver/qvos-launch-screensaver"
runner="$root/qvcore/screensaver/qvos-screensaver"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
launch_log="$test_root/launches"
focus_log="$test_root/focus"
effect_log="$test_root/effect"
cursor_log="$test_root/cursor"
cursor_keyword_log="$test_root/cursor-keywords"
client_poll_log="$test_root/client-polls"

cleanup() {
  [[ -d $test_root ]] && rm -rf "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin" "$test_root/.local/share/qvos/bin" "$test_root/.config/omarchy/branding" "$test_root/runtime"
printf 'qvOS\n' >"$test_root/.config/omarchy/branding/screensaver.txt"

install -m 0755 /dev/stdin "$test_root/.local/share/qvos/bin/qvos-screensaver" <<'SCRIPT'
#!/bin/bash

exit 0
SCRIPT

install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash

case $1 in
clients)
  if [[ ${QVOS_TEST_EXISTING:-0} == "1" ]]; then
    printf '[{"class":"org.omarchy.screensaver","address":"0xexisting"}]\n'
  else
    count=0
    [[ -f $QVOS_TEST_LAUNCH_LOG ]] && count="$(wc -l <"$QVOS_TEST_LAUNCH_LOG")"
    polls=0
    [[ -f $QVOS_TEST_CLIENT_POLL_LOG ]] && polls="$(wc -l <"$QVOS_TEST_CLIENT_POLL_LOG")"
    if ((count > 0 && polls == 0)); then
      jq -cn --argjson count "$count" '[range(0; $count) | {class: "org.omarchy.screensaver", address: ("0x" + (.|tostring))}]'
      printf 'active\n' >>"$QVOS_TEST_CLIENT_POLL_LOG"
    else
      printf '[]\n'
    fi
  fi
  ;;
monitors)
  printf '[{"name":"DP-1","focused":true},{"name":"DP-2","focused":false}]\n'
  ;;
getoption)
  [[ ${2:-} == "cursor:inactive_timeout" && ${3:-} == "-j" ]] || exit 1
  printf '{"float":7.5}\n'
  ;;
dispatch)
  case $2 in
  focusmonitor) printf '%s\n' "$3" >>"$QVOS_TEST_FOCUS_LOG" ;;
  exec)
    shift 2
    [[ ${1:-} == "--" ]] && shift
    printf '%s' "${1:-}" >>"$QVOS_TEST_LAUNCH_LOG"
    shift || true
    printf '\t%s' "$@" >>"$QVOS_TEST_LAUNCH_LOG"
    printf '\n' >>"$QVOS_TEST_LAUNCH_LOG"
    ;;
  closewindow) : ;;
  *) exit 1 ;;
  esac
  ;;
cursorpos)
  if [[ -s ${QVOS_TEST_CURSOR_LOG:-} ]]; then
    head -n 1 "$QVOS_TEST_CURSOR_LOG"
    sed -i '1d' "$QVOS_TEST_CURSOR_LOG"
  else
    printf '{"x":0,"y":0}\n'
  fi
  ;;
keyword)
  printf '%s=%s\n' "${2:-}" "${3:-}" >>"$QVOS_TEST_CURSOR_KEYWORD_LOG"
  ;;
*) exit 1 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/xdg-terminal-exec" <<'SCRIPT'
#!/bin/bash

[[ ${1:-} == "--print-id" ]] || exit 1
printf '%s\n' "${QVOS_TEST_TERMINAL:-Alacritty}"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash

[[ $1 == "tte" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-toggle-enabled" <<'SCRIPT'
#!/bin/bash

exit 1
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-hyprland-monitor-focused" <<'SCRIPT'
#!/bin/bash

printf 'DP-1\n'
SCRIPT

for command_name in walker notify-send; do
  install -m 0755 /dev/stdin "$test_bin/$command_name" <<'SCRIPT'
#!/bin/bash

exit 0
SCRIPT
done

install -m 0755 /dev/stdin "$test_bin/tte" <<'SCRIPT'
#!/bin/bash

printf '%s\n' "$*" >"$QVOS_TEST_EFFECT_LOG"
exec sleep 5
SCRIPT

run_launcher() {
  : >"$client_poll_log"
  QVOS_TEST_EXISTING="${QVOS_TEST_EXISTING:-0}" \
    QVOS_TEST_TERMINAL="${QVOS_TEST_TERMINAL:-Alacritty}" \
    QVOS_TEST_LAUNCH_LOG="$launch_log" \
    QVOS_TEST_FOCUS_LOG="$focus_log" \
    QVOS_TEST_CLIENT_POLL_LOG="$client_poll_log" \
    QVOS_TEST_CURSOR_KEYWORD_LOG="$cursor_keyword_log" \
    HOME="$test_root" \
    XDG_RUNTIME_DIR="$test_root/runtime" \
    PATH="$test_bin:/usr/bin" \
    "$launcher" "$@"
}

: >"$launch_log"
: >"$focus_log"
: >"$cursor_keyword_log"
run_launcher force
[[ "$(wc -l <"$launch_log")" == "2" ]] || fail "monitor launch count"
grep -F -- $'alacritty\t--class=org.omarchy.screensaver' "$launch_log" >/dev/null || fail "Alacritty command"
[[ "$(tail -n 1 "$focus_log")" == "DP-1" ]] || fail "focused monitor restoration"
pass "screensaver launches once per monitor and restores focus"

[[ $(cat "$cursor_keyword_log") == $'cursor:inactive_timeout=0.1\ncursor:inactive_timeout=7.5' ]] ||
  fail "cursor inactivity timeout lifecycle"
pass "external screensaver closure restores the previous cursor timeout"

: >"$launch_log"
QVOS_TEST_EXISTING="1" run_launcher force
[[ ! -s $launch_log ]] || fail "duplicate screensaver launch"
pass "an existing screensaver suppresses duplicate launches"

: >"$launch_log"
QVOS_TEST_TERMINAL="Ghostty" run_launcher force
grep -F -- $'ghostty\t--class=org.omarchy.screensaver' "$launch_log" >/dev/null || fail "Ghostty command"
pass "supported terminal selection builds the expected command"

: >"$launch_log"
if QVOS_TEST_TERMINAL="unsupported" run_launcher force >/dev/null 2>&1; then
  fail "unsupported terminal accepted"
fi
pass "unsupported terminals fail clearly"

set +e
run_launcher invalid >/dev/null 2>&1
usage_status=$?
set -e
((usage_status == 2)) || fail "launcher usage status"
pass "invalid launcher arguments show usage"

if HOME="$test_root" QVOS_SCREENSAVER_EFFECT_INDEX=15 PATH="$test_bin:/usr/bin" "$runner" >/dev/null 2>&1; then
  fail "invalid effect accepted"
fi
if HOME="$test_root" QVOS_SCREENSAVER_FRAME_RATE=0 PATH="$test_bin:/usr/bin" "$runner" >/dev/null 2>&1; then
  fail "invalid frame rate accepted"
fi
pass "effect and frame-rate bounds are validated"

: >"$launch_log"
{ sleep 0.1; printf 'x'; } | \
  QVOS_TEST_EFFECT_LOG="$effect_log" \
  QVOS_TEST_LAUNCH_LOG="$launch_log" \
  QVOS_TEST_FOCUS_LOG="$focus_log" \
  HOME="$test_root" \
  QVOS_SCREENSAVER_EFFECT_INDEX=0 \
  QVOS_SCREENSAVER_FRAME_RATE=144 \
  PATH="$test_bin:/usr/bin" \
  "$runner" >/dev/null
grep -F -- '--frame-rate 144' "$effect_log" >/dev/null || fail "frame-rate propagation"
grep -F -- ' rings ' "$effect_log" >/dev/null || fail "effect selection"
pass "keypress exit cleans up a running effect"

printf '%s\n' '{"x":0,"y":0}' '{"x":1,"y":0}' >"$cursor_log"
: >"$launch_log"
QVOS_TEST_CURSOR_LOG="$cursor_log" \
  QVOS_TEST_EFFECT_LOG="$effect_log" \
  QVOS_TEST_LAUNCH_LOG="$launch_log" \
  QVOS_TEST_FOCUS_LOG="$focus_log" \
  HOME="$test_root" \
  QVOS_SCREENSAVER_EFFECT_INDEX=0 \
  QVOS_SCREENSAVER_FRAME_RATE=144 \
  PATH="$test_bin:/usr/bin" \
  "$runner" </dev/null >/dev/null
pass "cursor movement exits the screensaver"

if rg -q 'on-resume\s*=\s*pkill.*org\.omarchy\.screensaver' "$root/qvcore/config/files/hypr/hypridle.conf"; then
  fail "idle resume can terminate a screensaver during launch"
fi
pass "idle config does not race screensaver startup"

if rg -q 'cursor:invisible\s+true' "$launcher" "$runner"; then
  fail "screensaver can leak a globally invisible cursor"
fi
pass "screensaver cursor hiding remains recoverable through pointer movement"
