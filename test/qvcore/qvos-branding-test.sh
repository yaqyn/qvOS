#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
test_bin="$test_root/bin"
event_log="$test_root/events"
branding_install="$root/qvcore/branding/install"
default_art="$root/qvcore/branding/terminal-art.txt"

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
printf '\033[31mlegacy ANSI\033[0m\n' \
  >"$test_home/.config/omarchy/branding/about-fastfetch.ansi"
printf 'custom About\n' >"$test_home/.config/omarchy/branding/about.txt"
printf 'custom screensaver\n' \
  >"$test_home/.config/omarchy/branding/screensaver.txt"
printf 'historical backup\n' \
  >"$test_home/.config/omarchy/branding/about.txt.bak.1"
: >"$event_log"

run_owner() {
  HOME="$test_home" \
    QVOS_PATH="$root" \
    QVOS_TEST_EVENT_LOG="$event_log" \
    PATH="$test_bin:$root/bin:/usr/bin" \
    "$@"
}

run_owner "$branding_install" >/dev/null
[[ $(<"$test_home/.config/qvos/branding/about.txt") == "custom About" ]] ||
  fail "plain legacy About preservation"
[[ $(<"$test_home/.config/qvos/branding/screensaver.txt") == \
  "custom screensaver" ]] || fail "legacy screensaver preservation"
[[ ! -e $test_home/.config/omarchy/branding ]] ||
  fail "legacy branding state remains active"
[[ $(stat -c '%a' "$test_home/.config/qvos/branding") == "700" ]] ||
  fail "private branding directory mode"
for target in about.txt screensaver.txt; do
  [[ $(stat -c '%a' "$test_home/.config/qvos/branding/$target") == "600" ]] ||
    fail "private branding file mode: $target"
done
backup_root="$test_home/.local/state/qvos/branding-backups"
[[ $(find "$backup_root" -maxdepth 1 -type f | wc -l) == "2" ]] ||
  fail "unsafe ANSI and historical backup preservation"
if rg -l $'\033' "$test_home/.config/qvos/branding"; then
  fail "terminal control sequences migrated into active branding"
fi

state_before=$(find "$test_home" -type f -printf '%P|%m|%i|%T@\n' | sort)
run_owner "$branding_install" >/dev/null
[[ $(find "$test_home" -type f -printf '%P|%m|%i|%T@\n' | sort) == \
  "$state_before" ]] || fail "idempotent branding install"

run_owner "$branding_install" --reset-defaults >/dev/null
for target in about.txt screensaver.txt; do
  cmp -s "$default_art" "$test_home/.config/qvos/branding/$target" ||
    fail "default terminal art reset: $target"
done
[[ $(find "$backup_root" -maxdepth 1 -type f | wc -l) == "4" ]] ||
  fail "custom qvOS branding backup on reset"

install -m 0755 /dev/stdin "$test_bin/qv-menu-file" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "${QVOS_TEST_IMAGE:-}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/qv-transcode-ascii" <<'SCRIPT'
#!/bin/bash
printf 'transcode' >>"$QVOS_TEST_EVENT_LOG"
printf '\t%s' "$@" >>"$QVOS_TEST_EVENT_LOG"
printf '\n' >>"$QVOS_TEST_EVENT_LOG"
SCRIPT
for command in \
  omarchy-launch-about \
  omarchy-launch-editor \
  qv-launch-screensaver; do
  install -m 0755 /dev/stdin "$test_bin/$command" <<'SCRIPT'
#!/bin/bash
printf '%s' "${0##*/}" >>"$QVOS_TEST_EVENT_LOG"
for argument in "$@"; do
  printf '\t%s' "$argument" >>"$QVOS_TEST_EVENT_LOG"
done
printf '\n' >>"$QVOS_TEST_EVENT_LOG"
SCRIPT
done

: >"$event_log"
run_owner "$root/qvcore/branding/about" reset
cmp -s "$default_art" "$test_home/.config/qvos/branding/about.txt" ||
  fail "About reset source"
grep -Fqx 'omarchy-launch-about' "$event_log" ||
  fail "About reset refresh"

: >"$event_log"
run_owner "$root/qvcore/branding/about" text
[[ $(<"$event_log") == \
  $'omarchy-launch-editor\t'"$test_home/.config/qvos/branding/about.txt"$'\nomarchy-launch-about' ]] ||
  fail "About text lifecycle"

: >"$event_log"
image="$test_home/logo image.png"
: >"$image"
QVOS_TEST_IMAGE="$image" run_owner "$root/qvcore/branding/about" image
[[ $(<"$event_log") == \
  $'transcode\t'"$image"$'\t'"$test_home/.config/qvos/branding/about.txt"$'\t--width\t54\t--height\t26\t--mode\tblock\nomarchy-launch-about' ]] ||
  fail "About image argument preservation"

: >"$event_log"
run_owner "$root/qvcore/branding/screensaver" reset
cmp -s "$default_art" \
  "$test_home/.config/qvos/branding/screensaver.txt" ||
  fail "screensaver reset source"
grep -Fqx $'qv-launch-screensaver\tforce' "$event_log" ||
  fail "screensaver reset refresh"

: >"$event_log"
QVOS_TEST_IMAGE="$image" run_owner "$root/qvcore/branding/screensaver" image
[[ $(<"$event_log") == \
  $'transcode\t'"$image"$'\t'"$test_home/.config/qvos/branding/screensaver.txt"$'\nqv-launch-screensaver\tforce' ]] ||
  fail "screensaver image argument preservation"

set +e
run_owner "$root/qvcore/branding/about" invalid >/dev/null 2>&1
about_status=$?
run_owner "$root/qvcore/branding/screensaver" invalid >/dev/null 2>&1
screensaver_status=$?
set -e
((about_status == 2 && screensaver_status == 2)) ||
  fail "invalid branding action status"

logo_output=$(TERM=xterm run_owner "$root/qvcore/branding/show-logo")
logo_first_line=$(head -n 1 "$default_art")
grep -Fq "$logo_first_line" <<<"$logo_output" ||
  fail "terminal art owner output"

unsafe_home="$test_root/unsafe-home"
external="$test_root/external"
install -d "$unsafe_home/.config" "$external"
printf 'outside\n' >"$external/about.txt"
ln -s "$external" "$unsafe_home/.config/qvos"
if HOME="$unsafe_home" QVOS_PATH="$root" "$branding_install" \
  >/dev/null 2>&1; then
  fail "symbolic-link branding root accepted"
fi
[[ $(<"$external/about.txt") == "outside" ]] ||
  fail "symbolic-link branding target preservation"

printf 'ok - qvOS branding has private native state and one preserved terminal-art owner\n'
