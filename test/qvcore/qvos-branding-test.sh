#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_home="$test_root/home"
test_bin="$test_root/bin"
event_log="$test_root/events"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

"$root/qvcore/branding/check"

install -d "$test_home/.config/omarchy/branding" "$test_bin"
: >"$event_log"

install -m 0755 /dev/stdin "$test_bin/omarchy-menu-file" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "${QVOS_TEST_IMAGE:-}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/omarchy-transcode-ascii" <<'SCRIPT'
#!/bin/bash
printf 'transcode' >>"$QVOS_TEST_EVENT_LOG"
printf '\t%s' "$@" >>"$QVOS_TEST_EVENT_LOG"
printf '\n' >>"$QVOS_TEST_EVENT_LOG"
SCRIPT
for command in \
  omarchy-launch-about \
  omarchy-launch-editor \
  omarchy-launch-screensaver; do
  install -m 0755 /dev/stdin "$test_bin/$command" <<'SCRIPT'
#!/bin/bash
printf '%s' "${0##*/}" >>"$QVOS_TEST_EVENT_LOG"
for argument in "$@"; do
  printf '\t%s' "$argument" >>"$QVOS_TEST_EVENT_LOG"
done
printf '\n' >>"$QVOS_TEST_EVENT_LOG"
SCRIPT
done

run_owner() {
  HOME="$test_home" \
    OMARCHY_PATH="$root" \
    QVOS_TEST_EVENT_LOG="$event_log" \
    PATH="$test_bin:/usr/bin" \
    "$@"
}

run_owner "$root/qvcore/branding/about" reset
cmp -s \
  "$root/qvcore/branding/icon.txt" \
  "$test_home/.config/omarchy/branding/about.txt" ||
  fail "About reset source"
grep -Fqx 'omarchy-launch-about' "$event_log" ||
  fail "About reset refresh"

: >"$event_log"
run_owner "$root/qvcore/branding/about" text
[[ $(<"$event_log") == \
  $'omarchy-launch-editor\t'"$test_home/.config/omarchy/branding/about.txt"$'\nomarchy-launch-about' ]] ||
  fail "About text lifecycle"

: >"$event_log"
image="$test_home/logo image.png"
: >"$image"
QVOS_TEST_IMAGE="$image" run_owner "$root/qvcore/branding/about" image
[[ $(<"$event_log") == \
  $'transcode\t'"$image"$'\t'"$test_home/.config/omarchy/branding/about.txt"$'\t--width\t54\t--height\t26\t--mode\tblock\nomarchy-launch-about' ]] ||
  fail "About image argument preservation"

: >"$event_log"
run_owner "$root/qvcore/branding/screensaver" reset
cmp -s \
  "$root/qvcore/branding/logo.txt" \
  "$test_home/.config/omarchy/branding/screensaver.txt" ||
  fail "screensaver reset source"
grep -Fqx $'omarchy-launch-screensaver\tforce' "$event_log" ||
  fail "screensaver reset refresh"

: >"$event_log"
QVOS_TEST_IMAGE="$image" run_owner "$root/qvcore/branding/screensaver" image
[[ $(<"$event_log") == \
  $'transcode\t'"$image"$'\t'"$test_home/.config/omarchy/branding/screensaver.txt"$'\nomarchy-launch-screensaver\tforce' ]] ||
  fail "screensaver image argument preservation"

if run_owner "$root/qvcore/branding/about" invalid >/dev/null 2>&1; then
  fail "invalid About action accepted"
fi
if run_owner "$root/qvcore/branding/screensaver" invalid >/dev/null 2>&1; then
  fail "invalid screensaver action accepted"
fi

logo_output=$(TERM=xterm run_owner "$root/qvcore/branding/show-logo")
logo_first_line=$(head -n 1 "$root/qvcore/branding/logo.txt")
grep -Fq "$logo_first_line" <<<"$logo_output" ||
  fail "terminal logo owner output"

printf 'ok - qvOS branding actions have one native owner and preserve compatibility\n'
