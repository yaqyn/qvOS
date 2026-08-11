#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_home="$test_root/home"
test_qvos="$test_root/qvos"
test_bin="$test_root/bin"
event_log="$test_root/events"
marker="$test_home/.local/state/qvos/install/first-run.mode"
test_helper="$test_root/first-run-root"
test_sudo="$test_root/sudo"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$test_bin" \
  "$test_home/.local/state/qvos/install" \
  "$test_qvos/qvcore/config" \
  "$test_qvos/qvcore/install/first-run" \
  "$test_qvos/qvcore/menu"
install -m 0755 "$root/qvcore/install/first-run/run" \
  "$test_qvos/qvcore/install/first-run/run"
: >"$event_log"
: >"$test_helper"
chmod 0755 "$test_helper"

install -m 0755 /dev/stdin "$test_sudo" <<'SCRIPT'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$QVOS_TEST_EVENT_LOG"
SCRIPT
first_run_paths=(
  qvcore/config/toggle-state
  qvcore/config/user-services
  qvcore/install/first-run/battery-monitor.sh
  qvcore/install/first-run/recover-internal-monitor.sh
  qvcore/install/first-run/swayosd.sh
  qvcore/install/first-run/gtk-primary-paste.sh
  qvcore/install/first-run/text-scaling.sh
  qvcore/install/first-run/elephant.sh
  qvcore/install/first-run/gnome-theme
  qvcore/install/first-run/icons
  qvcore/config/monitor-autodetect
  qvcore/menu/install
  qvcore/install/first-run/welcome.sh
  qvcore/install/first-run/wifi.sh
)
for path in "${first_run_paths[@]}"; do
  install -D -m 0755 /dev/stdin "$test_qvos/$path" <<'SCRIPT'
#!/bin/bash
path=${0#"$QVOS_TEST_SOURCE/"}
printf 'owner:%s:%s\n' "$path" "$*" >>"$QVOS_TEST_EVENT_LOG"
[[ ${QVOS_TEST_FAIL_PATH:-} != "$path" ]]
SCRIPT
done
run_first_run() {
  HOME="$test_home" \
    QVOS_PATH="$test_qvos" \
    QVOS_FIRST_RUN_TESTING=1 \
    QVOS_FIRST_RUN_ROOT_HELPER="$test_helper" \
    QVOS_FIRST_RUN_SUDO="$test_sudo" \
    QVOS_TEST_SOURCE="$test_qvos" \
    QVOS_TEST_EVENT_LOG="$event_log" \
    PATH="$test_bin:/usr/bin" \
    "$test_qvos/qvcore/install/first-run/run"
}

run_first_run
[[ ! -s $event_log ]] || fail "first run mutated without its marker"

: >"$marker"
chmod 0644 "$marker"
QVOS_TEST_FAIL_PATH=qvcore/install/first-run/icons \
  run_first_run >/dev/null 2>&1 && fail "first-run owner ignored a required failure"
[[ -f $marker ]] || fail "failed first run removed its retry marker"
[[ $(stat -c '%a' "$marker") == "600" ]] ||
  fail "first run did not privatize its marker"
if grep -Fq "sudo:$test_helper cleanup" "$event_log"; then
  fail "failed first run removed its privilege retry path"
fi
if grep -Fq 'owner:qvcore/install/first-run/welcome.sh:' "$event_log"; then
  fail "failed first run showed completion notifications"
fi

: >"$event_log"
run_first_run
expected_run=$(printf '%s\n' \
  "sudo:$test_helper apply" \
  'owner:qvcore/config/toggle-state:' \
  'owner:qvcore/config/user-services:' \
  'owner:qvcore/install/first-run/battery-monitor.sh:' \
  'owner:qvcore/install/first-run/recover-internal-monitor.sh:' \
  'owner:qvcore/install/first-run/swayosd.sh:' \
  'owner:qvcore/install/first-run/gtk-primary-paste.sh:' \
  'owner:qvcore/install/first-run/text-scaling.sh:' \
  'owner:qvcore/install/first-run/elephant.sh:' \
  'owner:qvcore/install/first-run/gnome-theme:' \
  'owner:qvcore/install/first-run/icons:' \
  'owner:qvcore/config/monitor-autodetect:' \
  'owner:qvcore/menu/install:--install' \
  "sudo:$test_helper cleanup" \
  'owner:qvcore/install/first-run/welcome.sh:' \
  'owner:qvcore/install/first-run/wifi.sh:')
[[ $(<"$event_log") == "$expected_run" ]] ||
  fail "ordered first-run lifecycle"
[[ ! -e $marker ]] || fail "successful first run kept its marker"

: >"$marker"
chmod 0600 "$marker"
: >"$event_log"
QVOS_TEST_FAIL_PATH=qvcore/install/first-run/welcome.sh \
  run_first_run >/dev/null 2>&1
[[ ! -e $marker ]] || fail "notification failure changed readiness"
grep -Fq 'owner:qvcore/install/first-run/wifi.sh:' "$event_log" ||
  fail "one notification failure suppressed the other"

: >"$marker"
chmod 0600 "$marker"
lock_file="$test_home/.local/state/qvos/install/first-run.lock"
install -d "${lock_file%/*}"
exec 8>"$lock_file"
flock -n 8
: >"$event_log"
run_first_run
[[ ! -s $event_log && -f $marker ]] ||
  fail "concurrent first run crossed its lock"
[[ $(stat -c '%a' "$lock_file") == "600" ]] ||
  fail "first-run lock is not private"
flock -u 8

rm -rf -- "${lock_file%/*}"
state_target="$test_root/state-target"
ln -s "$state_target" "${lock_file%/*}"
: >"$event_log"
if run_first_run >/dev/null 2>&1; then
  fail "first run accepted a symbolic-link state directory"
fi
[[ ! -e $state_target && ! -s $event_log ]] ||
  fail "first run followed a symbolic-link state directory"
rm -f -- "${lock_file%/*}"

install -d "${marker%/*}"
rm -f -- "$marker"
marker_target="$test_root/marker-target"
ln -s "$marker_target" "$marker"
if run_first_run >/dev/null 2>&1; then
  fail "first run accepted a symbolic-link marker"
fi
[[ ! -e $marker_target ]] || fail "first run followed a symbolic-link marker"

visual_home="$test_root/visual-home"
visual_events="$test_root/visual-events"
install -d "$visual_home" "$test_bin"
: >"$visual_events"
install -m 0755 /dev/stdin "$test_bin/gsettings" <<'SCRIPT'
#!/bin/bash
printf 'gsettings:%s\n' "$*" >>"$QVOS_VISUAL_EVENT_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/gtk-update-icon-cache" <<'SCRIPT'
#!/bin/bash
printf 'icon-cache:%s\n' "$*" >>"$QVOS_VISUAL_EVENT_LOG"
SCRIPT
HOME="$visual_home" QVOS_VISUAL_EVENT_LOG="$visual_events" \
PATH="$test_bin:/usr/bin" "$root/qvcore/install/first-run/gnome-theme"
if grep -Fq 'icon-theme' "$visual_events"; then
  fail "GNOME owner duplicated icon-theme ownership"
fi
HOME="$visual_home" QVOS_VISUAL_EVENT_LOG="$visual_events" \
PATH="$test_bin:/usr/bin" "$root/qvcore/install/first-run/icons"
icon_theme="$visual_home/.local/share/icons/qv-Papirus-Dark"
[[ -f $icon_theme/index.theme && ! -L $icon_theme/index.theme ]] ||
  fail "native qvOS icon theme"
grep -Fqx \
  'gsettings:set org.gnome.desktop.interface icon-theme qv-Papirus-Dark' \
  "$visual_events" || fail "singular icon-theme application"

printf 'ok - qvOS first run is ordered, retry-safe, locked, and singular\n'
