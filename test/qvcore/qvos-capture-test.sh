#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_root=""

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

cleanup() {
  local pid
  local state=${XDG_RUNTIME_DIR:-}/qvos-capture/screenrecord.state

  if [[ -f $state && ! -L $state ]]; then
    pid=$(cut -f2 "$state" 2>/dev/null || true)
    [[ $pid =~ ^[1-9][0-9]*$ ]] && kill -TERM "$pid" 2>/dev/null || true
  fi
  [[ -z $test_root || ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

test_root=$(mktemp -d)
test_bin="$test_root/bin"
test_log="$test_root/log"
export HOME="$test_root/home"
export XDG_RUNTIME_DIR="$test_root/runtime"
export XDG_STATE_HOME="$test_root/state"
export QVOS_CAPTURE_TESTING=1
export QVOS_PATH=$root
export QVOS_SCREENSHOT_DIR="$test_root/pictures"
export QVOS_SCREENRECORD_DIR="$test_root/videos"
export MOCK_LOG=$test_log
install -d -m 0700 \
  "$HOME" \
  "$XDG_RUNTIME_DIR" \
  "$test_bin" \
  "$test_log" \
  "$QVOS_SCREENSHOT_DIR" \
  "$QVOS_SCREENRECORD_DIR"
export PATH="$test_bin:$root/bin:/usr/bin"

cat >"$test_bin/qv-cmd-missing" <<'SCRIPT'
#!/bin/bash
case ",${MOCK_MISSING_COMMANDS:-}," in
*,"$1",*) exit 0 ;;
esac
command -v -- "$1" >/dev/null 2>&1 && exit 1
exit 0
SCRIPT
cat >"$test_bin/qv-cmd-present" <<'SCRIPT'
#!/bin/bash
case ",${MOCK_MISSING_COMMANDS:-}," in
*,"$1",*) exit 1 ;;
esac
command -v -- "$1" >/dev/null 2>&1
SCRIPT
cat >"$test_bin/qv-notification-send" <<'SCRIPT'
#!/bin/bash
printf '%q ' "$@" >>"$MOCK_LOG/qv-notifications"
printf '\n' >>"$MOCK_LOG/qv-notifications"
SCRIPT
cat >"$test_bin/notify-send" <<'SCRIPT'
#!/bin/bash
printf '%q ' "$@" >>"$MOCK_LOG/notifications"
printf '\n' >>"$MOCK_LOG/notifications"
printf '%s' "${MOCK_NOTIFY_ACTION:-}"
SCRIPT
cat >"$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
monitors)
  dpms=${MOCK_DPMS_STATUS:-true}
  cat <<JSON
[
  {"name":"DP-1","x":0,"y":0,"width":1280,"height":720,"scale":1,"transform":0,"focused":false,"dpmsStatus":true,"activeWorkspace":{"id":2}},
  {"name":"eDP-1","x":-1080,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"focused":true,"dpmsStatus":$dpms,"activeWorkspace":{"id":1}}
]
JSON
  ;;
clients)
  cat <<'JSON'
[
  {"workspace":{"id":1},"at":[-900,100],"size":[800,600]},
  {"workspace":{"id":2},"at":[50,50],"size":[500,400]}
]
JSON
  ;;
*) exit 2 ;;
esac
SCRIPT
cat >"$test_bin/hyprpicker" <<'SCRIPT'
#!/bin/bash
trap 'exit 0' TERM INT
while :; do
  sleep 1
done
SCRIPT
cat >"$test_bin/slurp" <<'SCRIPT'
#!/bin/bash
[[ ${MOCK_SLURP_STATUS:-0} == "0" ]] || exit "$MOCK_SLURP_STATUS"
printf '%s\n' "${MOCK_SLURP_SELECTION:--900,100 800x600}"
SCRIPT
cat >"$test_bin/grim" <<'SCRIPT'
#!/bin/bash
printf '%q ' "$@" >>"$MOCK_LOG/grim"
printf '\n' >>"$MOCK_LOG/grim"
[[ ${MOCK_GRIM_FAIL:-0} == "0" ]] || exit 1
destination=${!#}
if [[ $destination == "-" ]]; then
  printf 'mock-png'
else
  printf 'mock-png' >"$destination"
fi
SCRIPT
cat >"$test_bin/wl-copy" <<'SCRIPT'
#!/bin/bash
bytes=$(wc -c)
printf '%s\t%s\n' "$bytes" "$*" >>"$MOCK_LOG/clipboard"
[[ ${MOCK_WL_COPY_FAIL:-0} == "0" ]]
SCRIPT
cat >"$test_bin/satty" <<'SCRIPT'
#!/bin/bash
printf '%q ' "$@" >>"$MOCK_LOG/editor"
printf '\n' >>"$MOCK_LOG/editor"
SCRIPT
cat >"$test_bin/tesseract" <<'SCRIPT'
#!/bin/bash
if [[ ${1:-} == "--list-langs" ]]; then
  printf 'List of available languages (2):\neng\nara\n'
  exit
fi
printf '%s\n' "${MOCK_OCR_TEXT:-qvOS fixture text}"
SCRIPT
cat >"$test_bin/timeout" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} != "--foreground" ]] || shift
shift
exec "$@"
SCRIPT
cat >"$test_bin/gpu-screen-recorder" <<'PY'
#!/usr/bin/python3
import os
import signal
import sys
import time

output = None
for index, argument in enumerate(sys.argv[:-1]):
    if argument == "-o":
        output = sys.argv[index + 1]
if output is None:
    sys.exit(2)
time.sleep(float(os.environ.get("MOCK_RECORDER_START_DELAY", "0")))
with open(output, "wb") as recording:
    recording.write(b"mock-video")

signal.signal(signal.SIGINT, lambda _signal, _frame: sys.exit(0))
signal.signal(signal.SIGTERM, lambda _signal, _frame: sys.exit(0))
while True:
    time.sleep(0.05)
PY
cat >"$test_bin/ffprobe" <<'SCRIPT'
#!/bin/bash
if [[ $* == *packet=flags* ]]; then
  exit
fi
if [[ $* == *stream=codec_type* ]]; then
  exit
fi
printf '1.0\n'
SCRIPT
cat >"$test_bin/ffmpeg" <<'SCRIPT'
#!/bin/bash
destination=""
for argument in "$@"; do
  case $argument in
  *.mp4 | *.png) destination=$argument ;;
  esac
done
[[ -n $destination ]] || exit 2
printf 'mock-processed-media' >"$destination"
SCRIPT
cat >"$test_bin/pkill" <<'SCRIPT'
#!/bin/bash
printf '%q ' "$@" >>"$MOCK_LOG/pkill"
printf '\n' >>"$MOCK_LOG/pkill"
exit 1
SCRIPT
cat >"$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf '%q ' "$@" >>"$MOCK_LOG/systemctl"
printf '\n' >>"$MOCK_LOG/systemctl"
if [[ $* == "--user is-active --quiet qvos-color-picker.service" ]]; then
  [[ ${MOCK_COLOR_ACTIVE:-0} == "1" ]]
fi
SCRIPT
cat >"$test_bin/systemd-run" <<'SCRIPT'
#!/bin/bash
printf '%q ' "$@" >>"$MOCK_LOG/systemd-run"
printf '\n' >>"$MOCK_LOG/systemd-run"
SCRIPT
cat >"$test_bin/mpv" <<'SCRIPT'
#!/bin/bash
printf '%q\n' "$*" >>"$MOCK_LOG/mpv"
SCRIPT
chmod 0755 "$test_bin"/*

screenshot="$root/qvcore/capture/screenshot"
color="$root/qvcore/capture/color"
ocr="$root/qvcore/capture/ocr"
screenrecord="$root/qvcore/capture/screenrecord"
indicator="$root/qvcore/capture/status"
state="$XDG_RUNTIME_DIR/qvos-capture/screenrecord.state"

MOCK_COLOR_ACTIVE=1 "$color"
grep -Fq -- '--user stop qvos-color-picker.service' "$test_log/systemctl" ||
  fail "active Color Picker stop"
MOCK_COLOR_ACTIVE=0 "$color"
grep -Fq -- '--unit=qvos-color-picker.service' "$test_log/systemd-run" ||
  fail "named Color Picker launch"
grep -Fq -- 'hyprpicker -a' "$test_log/systemd-run" ||
  fail "Color Picker arguments"
pass "Color Picker toggles only its exact transient user service"

output=$($screenshot fullscreen save)
saved=${output#Saved screenshot: }
[[ -f $saved && $(stat -c '%a' "$saved") == "600" ]] ||
  fail "private fullscreen screenshot"
grep -Fq -- '-g -1080\,0\ 1920x1080' "$test_log/grim" ||
  fail "fullscreen uses focused monitor"
pass "fullscreen screenshot uses the focused monitor and private output"

export MOCK_DPMS_STATUS=false
before=$(find "$QVOS_SCREENSHOT_DIR" -maxdepth 1 -type f | wc -l)
set +e
$screenshot fullscreen save >/dev/null 2>&1
status=$?
set -e
after=$(find "$QVOS_SCREENSHOT_DIR" -maxdepth 1 -type f | wc -l)
[[ $status == "1" && $after == "$before" ]] || fail "powered-off screenshot refusal"
unset MOCK_DPMS_STATUS
pass "powered-off focused outputs fail before requesting a compositor frame"

$screenshot fullscreen save >/dev/null
(( $(find "$QVOS_SCREENSHOT_DIR" -maxdepth 1 -type f -name 'screenshot-*.png' | wc -l) == 2 )) ||
  fail "screenshot no-clobber naming"
pass "same-second screenshots do not overwrite one another"

export MOCK_SLURP_SELECTION='-1079,1 1x1'
$screenshot smart save >/dev/null
tail -n 1 "$test_log/grim" | grep -Fq -- '-g -1080\,0\ 1920x1080' ||
  fail "smart click monitor snap"
pass "smart selection supports negative coordinates and snaps tiny clicks"

export MOCK_SLURP_STATUS=1
set +e
$screenshot region save >/dev/null 2>&1
status=$?
set -e
(( status == 130 )) || fail "screenshot cancellation status"
unset MOCK_SLURP_STATUS
pass "screenshot cancellation is distinct and leaves no output"

export MOCK_WL_COPY_FAIL=1
before=$(find "$QVOS_SCREENSHOT_DIR" -maxdepth 1 -type f | wc -l)
$screenshot fullscreen slurp >/dev/null
after=$(find "$QVOS_SCREENSHOT_DIR" -maxdepth 1 -type f | wc -l)
(( after == before + 1 )) || fail "clipboard degradation preserves screenshot"
unset MOCK_WL_COPY_FAIL
pass "clipboard failure preserves the saved screenshot"

export MOCK_MISSING_COMMANDS=wl-copy,notify-send,satty
before=$(find "$QVOS_SCREENSHOT_DIR" -maxdepth 1 -type f | wc -l)
$screenshot fullscreen slurp >/dev/null
after=$(find "$QVOS_SCREENSHOT_DIR" -maxdepth 1 -type f | wc -l)
(( after == before + 1 )) || fail "missing optional screenshot tools"
grep -Fq 'Screenshot\ saved' "$test_log/qv-notifications" ||
  fail "fallback screenshot notification"
unset MOCK_MISSING_COMMANDS
pass "missing clipboard, editor, and notification tools do not lose a screenshot"

set +e
$screenshot fullscreen invalid >/dev/null 2>&1
status=$?
set -e
(( status == 2 )) || fail "invalid screenshot arguments"
pass "invalid screenshot input fails before capture"

export MOCK_SLURP_SELECTION='-900,100 800x600'
$ocr --langs=eng+ara >/dev/null
tail -n 1 "$test_log/clipboard" | grep -Fq 'text/plain;charset=utf-8' ||
  fail "OCR clipboard type"
if find "$XDG_RUNTIME_DIR/qvos-capture" -maxdepth 1 -name '.ocr.*' -print -quit |
  grep -q .; then
  fail "OCR temporary cleanup"
fi
pass "OCR validates installed languages, bounds output, and cleans private state"

set +e
$ocr --langs=fra >/dev/null 2>&1
status=$?
set -e
(( status == 1 )) || fail "missing OCR language status"
export MOCK_SLURP_STATUS=1
set +e
$ocr >/dev/null 2>&1
status=$?
set -e
(( status == 130 )) || fail "OCR cancellation status"
unset MOCK_SLURP_STATUS
pass "OCR rejects missing languages and preserves cancellation semantics"

transition_binary="$test_root/process-transition/gpu-screen-recorder"
install -D -m 0755 /usr/bin/sleep "$transition_binary"
(
  unset QVOS_CAPTURE_TESTING
  # shellcheck source=qvcore/capture/lib disable=SC1091
  source "$root/qvcore/capture/lib"
  transition_pid=""
  # shellcheck disable=SC2329 # Invoked by the EXIT trap.
  cleanup_transition() {
    [[ $transition_pid =~ ^[1-9][0-9]*$ ]] || return 0
    kill "$transition_pid" 2>/dev/null || true
    wait "$transition_pid" 2>/dev/null || true
  }
  trap cleanup_transition EXIT

  bash -c 'sleep 0.2; exec "$1" 5' _ "$transition_binary" &
  transition_pid=$!
  transition_start=$(capture_process_start "$transition_pid") ||
    fail "capture child process start token"
  capture_wait_for_process_match \
    "$transition_pid" gpu-screen-recorder "$transition_start" 20 ||
    fail "capture child executable transition"
)
pass "capture startup follows the exact child through its executable transition"

export MOCK_RECORDER_START_DELAY=5.2
$screenrecord >/dev/null
unset MOCK_RECORDER_START_DELAY
[[ -f $state && ! -L $state && $(stat -c '%a' "$state") == "600" ]] ||
  fail "private screen-recording state"
[[ $($screenrecord --status) == "active" ]] || fail "active recording status"
[[ $($indicator) == *'"class":"active"'* ]] || fail "active Waybar indicator"
recorder_pid=$(cut -f2 "$state")
kill -0 "$recorder_pid" 2>/dev/null || fail "recorded exact recorder PID"
pass "screen recording starts with private exact-PID state"

original_state=$(<"$state")
IFS=$'\t' read -r -a state_fields <<<"$original_state"
state_fields[2]=$((state_fields[2] + 1))
(
  IFS=$'\t'
  printf '%s\n' "${state_fields[*]}"
) >"$state"
chmod 0600 "$state"
[[ $($screenrecord --status) == "unsafe" ]] ||
  fail "recording process-instance mismatch"
kill -0 "$recorder_pid" 2>/dev/null || fail "mismatched state signaled recorder"
printf '%s\n' "$original_state" >"$state"
chmod 0600 "$state"
pass "process start tokens prevent PID-reuse signaling and unsafe recovery"

stop_stderr="$test_root/stop.stderr"
$screenrecord --stop-recording >/dev/null 2>"$stop_stderr"
[[ ! -s $stop_stderr ]] || fail "recording stop emitted a process-race error"
[[ ! -e $state && ! -L $state ]] || fail "recording state cleanup"
(( $(find "$QVOS_SCREENRECORD_DIR" -maxdepth 1 -type f -name 'screenrecording-*.mp4' | wc -l) == 1 )) ||
  fail "recording publication"
recording=$(find "$QVOS_SCREENRECORD_DIR" -maxdepth 1 -type f -name 'screenrecording-*.mp4')
[[ $(stat -c '%a' "$recording") == "600" ]] || fail "recording output mode"
[[ $($screenrecord --status) == "inactive" ]] || fail "inactive recording status"
[[ $($indicator) == '{"text":""}' ]] || fail "inactive Waybar indicator"
pass "screen recording stops only its tracked PID and publishes privately"

$screenrecord >/dev/null
export MOCK_MISSING_COMMANDS=ffmpeg,notify-send
$screenrecord --stop-recording >/dev/null
unset MOCK_MISSING_COMMANDS
(( $(find "$QVOS_SCREENRECORD_DIR" -maxdepth 1 -type f -name 'screenrecording-*.mp4' | wc -l) == 2 )) ||
  fail "recording preservation without FFmpeg"
grep -Fq 'Screen\ recording\ saved' "$test_log/qv-notifications" ||
  fail "fallback recording notification"
pass "missing post-processing and notification tools preserve the recording"

$screenrecord >/dev/null
recorder_pid=$(cut -f2 "$state")
kill -TERM "$recorder_pid"
for ((attempt = 0; attempt < 50; attempt++)); do
  kill -0 "$recorder_pid" 2>/dev/null || break
  sleep 0.02
done
[[ $($screenrecord --status) == "stale" ]] || fail "stale recording status"
$screenrecord >/dev/null
[[ ! -e $state ]] || fail "stale state cleanup"
(( $(find "$QVOS_SCREENRECORD_DIR" -maxdepth 1 -type f -name 'screenrecording-*.mp4' | wc -l) == 3 )) ||
  fail "stale recording recovery"
pass "interrupted valid recordings are recovered without starting a duplicate"

printf 'unsafe\n' >"$test_root/unsafe-state"
ln -s "$test_root/unsafe-state" "$state"
set +e
unsafe_status=$($screenrecord --status)
status=$?
set -e
[[ $unsafe_status == "unsafe" && $status == 1 ]] || fail "unsafe state rejection"
[[ $($indicator) == *'"class":"critical"'* ]] || fail "unsafe Waybar indicator"
unlink -- "$state"
pass "unsafe recording state is visible and rejected without mutation"

set +e
$screenrecord --resolution=8x8 >/dev/null 2>&1
status=$?
set -e
(( status == 2 )) || fail "recording resolution bounds"
set +e
$screenrecord --stop-recording >/dev/null 2>&1
status=$?
set -e
(( status == 1 )) || fail "inactive stop-only status"
pass "screen-recording validation prevents accidental start and invalid geometry"

"$root/qvcore/capture/check" >/dev/null
pass "Capture source ownership contract passes"
