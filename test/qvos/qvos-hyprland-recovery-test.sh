#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
repair="$root/qv/maintenance/qvos-repair"
test_root="$(mktemp -d)"
test_home="$test_root/home"
test_bin="$test_root/bin"
locker_bin="$test_root/locker-bin"
state="$test_root/state"
signature="qvos_recovery_test_$$"
socket="wayland-qvos-test"
runtime_dir="/run/user/$UID"
instance_root="$runtime_dir/hypr/$signature"
compositor_pid=""
spawned_pids=()

cleanup() {
  local pid

  for pid in "${spawned_pids[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  if [[ -n $compositor_pid ]]; then
    kill "$compositor_pid" 2>/dev/null || true
  fi
  rm -rf "$instance_root" "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$test_home/.config/hypr" \
  "$test_bin" \
  "$locker_bin" \
  "$state/pacman" \
  "$state/sys" \
  "$instance_root"
printf 'source = ~/.config/hypr/qv.conf\n' \
  >"$test_home/.config/hypr/hyprland.conf"
printf 'misc { allow_session_lock_restore = true }\n' \
  >"$test_home/.config/hypr/qv.conf"
touch "$state/pacman.log" "$state/actions.log"
cp /usr/bin/sleep "$locker_bin/hyprlock"

install -m 0755 /dev/stdin "$test_bin/Hyprland" <<'SCRIPT'
#!/bin/bash
if [[ ${1:-} == "--verify-config" ]]; then
  [[ ! -e $QVOS_TEST_STATE/offline-config-bad ]]
  exit
fi
while true; do
  sleep 1
done
SCRIPT

install -m 0755 /dev/stdin "$test_bin/hyprlock" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$$" >"$QVOS_TEST_STATE/replacement-pid"
if [[ ${QVOS_TEST_HYPRLOCK_MODE:-healthy} == "fail" ]]; then
  exit 1
fi
while true; do
  sleep 1
done
SCRIPT

install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

if [[ ${1:-} == "instances" ]]; then
  printf 'instance %s:\n' "$QVOS_TEST_SIGNATURE"
  printf '\ttime: 1\n'
  printf '\tpid: %s\n' "$QVOS_TEST_COMPOSITOR_PID"
  printf '\twl socket: %s\n\n' "$QVOS_TEST_SOCKET"
elif [[ ${1:-} == "--instance" ]]; then
  signature=$2
  command=$3
  [[ $signature == "$QVOS_TEST_SIGNATURE" ]] || exit 2
  case $command in
  configerrors)
    [[ ! -e $QVOS_TEST_STATE/live-config-bad ]] ||
      echo "test live config error"
    ;;
  monitors)
    cat <<MONITORS
Monitor TEST-1 (ID 0):
  1920x1080@60.00 at 0x0
  dpmsStatus: ${QVOS_TEST_DPMS_STATUS:-0}
  disabled: false

Monitor DISABLED-1 (ID 1):
  1280x720@60.00 at 0x0
  dpmsStatus: 1
  disabled: true
MONITORS
    ;;
  systeminfo)
    cat <<INFO
Backend: test-drm
INFO
    ;;
  dispatch)
    printf 'dispatch\t%s\t%s\n' "$signature" "$*" \
      >>"$QVOS_TEST_STATE/actions.log"
    ;;
  eval)
    printf 'eval\t%s\t%s\n' "$signature" "$4" \
      >>"$QVOS_TEST_STATE/actions.log"
    ;;
  *)
    exit 2
    ;;
  esac
else
  exit 2
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

case ${1:-} in
choose)
  echo "Recover Hyprland sad-face lock screen"
  ;;
confirm)
  if [[ ${QVOS_TEST_CONFIRM_INVALIDATE_INSTANCE:-0} == "1" ]]; then
    printf '%s\n%s\n' \
      "$((QVOS_TEST_COMPOSITOR_PID + 1))" \
      "$QVOS_TEST_SOCKET" \
      >"/run/user/$UID/hypr/$QVOS_TEST_SIGNATURE/hyprland.lock"
  fi
  if [[ ${QVOS_TEST_CONFIRM_SPAWN_LOCKER:-0} == "1" ]]; then
    env \
      HYPRLAND_INSTANCE_SIGNATURE="$QVOS_TEST_SIGNATURE" \
      WAYLAND_DISPLAY="$QVOS_TEST_SOCKET" \
      XDG_RUNTIME_DIR="/run/user/$UID" \
      "$QVOS_TEST_LOCKER_BINARY" 60 \
      </dev/null >/dev/null 2>&1 &
    printf '%s\n' "$!" >"$QVOS_TEST_STATE/confirmed-locker-pid"
  fi
  [[ ${QVOS_TEST_CONFIRM:-0} == "1" ]]
  ;;
*)
  exit 2
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/pacman" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
-Dk) echo "No database errors have been found!" ;;
-Qq)
  sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' \
    "$OMARCHY_PATH/qv/maintenance/essential-packages"
  printf '%s\n' linux linux-firmware
  ;;
-Qk)
  shift
  for package in "$@"; do
    echo "$package: 1 total file, 0 missing files"
  done
  ;;
-Qkk)
  shift
  for package in "$@"; do
    echo "$package: 1 total file, 0 altered files"
  done
  ;;
-Qqo) echo "linux" ;;
*) exit 2 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/git" <<'SCRIPT'
#!/bin/bash
exec /usr/bin/git "$@"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/uname" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "-r" ]] && echo "test-kernel"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/dkms" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/modinfo" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
install -m 0755 /dev/stdin "$test_bin/omarchy-hw-nvidia-gsp" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
install -m 0755 /dev/stdin "$test_bin/omarchy-hw-nvidia-without-gsp" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT

install -m 0755 /dev/stdin "$test_bin/findmnt" <<'SCRIPT'
#!/bin/bash
if [[ $* == *"-o TARGET"* ]]; then
  echo "/boot"
else
  echo "rw,relatime"
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/df" <<'SCRIPT'
#!/bin/bash
target=${2:-/}
if [[ ${1:-} == "-Pi" ]]; then
  printf 'Filesystem Inodes IUsed IFree IUse%% Mounted on\n'
  printf 'test 100000 1 99999 1%% %s\n' "$target"
else
  printf 'Filesystem Blocks Used Available Capacity Mounted on\n'
  printf 'test 20000000 1 10000000 1%% %s\n' "$target"
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/ip" <<'SCRIPT'
#!/bin/bash
echo "default via 192.0.2.1"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/getent" <<'SCRIPT'
#!/bin/bash
echo "192.0.2.2 STREAM archlinux.org"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/curl" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/timedatectl" <<'SCRIPT'
#!/bin/bash
echo "yes"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
arguments=" $* "
if [[ $arguments == *" --user list-units "* ]]; then
  if [[ -e $QVOS_TEST_STATE/uwsm-failed ]]; then
    echo "wayland-wm@test.service loaded failed failed Test"
  else
    echo "wayland-wm@test.service loaded active running Test"
  fi
elif [[ $arguments == *" --user show wayland-session-waitenv.service "* ]]; then
  [[ ! -e $QVOS_TEST_STATE/waitenv-failed ]] || echo "timeout"
elif [[ $arguments == *" is-failed "* ]]; then
  exit 1
elif [[ $arguments == *" is-enabled "* ]]; then
  exit 0
elif [[ $arguments == *" --user is-active "* ]]; then
  exit 0
else
  exit 2
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/busctl" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/journalctl" <<'SCRIPT'
#!/bin/bash
[[ ! -e $QVOS_TEST_STATE/journal-crash ]] || echo "Hyprland fatal crash"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/coredumpctl" <<'SCRIPT'
#!/bin/bash
printf 'coredumpctl\t%s\n' "$*" >>"$QVOS_TEST_STATE/actions.log"
[[ ! -e $QVOS_TEST_STATE/coredump ]] || echo "test Hyprland coredump"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "-v" ]] && exit
exec "$@"
SCRIPT

env \
  WAYLAND_DISPLAY="$socket" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" \
  QVOS_TEST_STATE="$state" \
  "$test_bin/Hyprland" compositor &
compositor_pid=$!
sleep 0.2
[[ $(<"/proc/$compositor_pid/comm") == "Hyprland" ]] ||
  fail "fake compositor process identity"
printf '%s\n%s\n' "$compositor_pid" "$socket" \
  >"$instance_root/hyprland.lock"
touch "$instance_root/hyprland.log"

run_repair() {
  HOME="$test_home" \
    XDG_CACHE_HOME="$state/cache" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    OMARCHY_PATH="$root" \
    QVOS_PACMAN_DB_PATH="$state/pacman" \
    QVOS_PACMAN_LOG="$state/pacman.log" \
    QVOS_SYS_ROOT="$state/sys" \
    QVOS_TEST_STATE="$state" \
    QVOS_TEST_SIGNATURE="$signature" \
    QVOS_TEST_SOCKET="$socket" \
    QVOS_TEST_COMPOSITOR_PID="$compositor_pid" \
    QVOS_TEST_LOCKER_BINARY="$locker_bin/hyprlock" \
    QVOS_TEST_HYPRLOCK_MODE="${QVOS_TEST_HYPRLOCK_MODE:-healthy}" \
    QVOS_TEST_CONFIRM="${QVOS_TEST_CONFIRM:-0}" \
    QVOS_TEST_CONFIRM_SPAWN_LOCKER="${QVOS_TEST_CONFIRM_SPAWN_LOCKER:-0}" \
    QVOS_TEST_CONFIRM_INVALIDATE_INSTANCE="${QVOS_TEST_CONFIRM_INVALIDATE_INSTANCE:-0}" \
    QVOS_INTEGRITY_WORKERS=2 \
    PATH="$test_bin:/usr/bin" \
    "$repair" "$@"
}

health_output=$(run_repair --status)
grep -Fq "[Repairable   ] hyprland.outputs-$signature" <<<"$health_output" ||
  fail "all-disabled DPMS output finding"
grep -Fq 'modes: TEST-1 1920x1080@60.00 at 0x0' <<<"$health_output" ||
  fail "monitor mode evidence"
if grep -Fq '1 of 1 enabled output(s) have DPMS on' <<<"$health_output"; then
  fail "disabled awake output is counted as enabled"
fi
grep -Fq "hyprland.log-$signature" <<<"$health_output" ||
  fail "exact compositor log location"
grep -Fq 'backend test-drm' <<<"$health_output" ||
  fail "compositor backend evidence"
pass "validated instance, output mode, DPMS, and log evidence are inspectable"

touch "$state/uwsm-failed" "$state/waitenv-failed" "$state/coredump"
failure_output=$(run_repair --status)
grep -Fq '[Blocked      ] hyprland.uwsm-failed' <<<"$failure_output" ||
  fail "failed exact UWSM unit"
grep -Fq '[Informational] hyprland.uwsm-waitenv' <<<"$failure_output" ||
  fail "UWSM wait-environment evidence"
grep -Fq '[Informational] hyprland.coredumps' <<<"$failure_output" ||
  fail "current-boot coredump evidence"
grep -Fq 'list Hyprland' "$state/actions.log" ||
  fail "Hyprland coredump query"
grep -Fq 'list hyprlock' "$state/actions.log" ||
  fail "hyprlock coredump query"
rm -f "$state/uwsm-failed" "$state/waitenv-failed" "$state/coredump"
pass "UWSM and compositor crash evidence is surfaced without session mutation"

: >"$state/actions.log"
replacement_output=$(QVOS_TEST_HYPRLOCK_MODE=healthy run_repair)
grep -Fq 'Replacement hyprlock PID' <<<"$replacement_output" ||
  fail "replacement locker healthy result"
if grep -Fq $'eval\t' "$state/actions.log"; then
  fail "healthy replacement clears the lock"
fi
replacement_pid=$(<"$state/replacement-pid")
spawned_pids+=("$replacement_pid")
kill "$replacement_pid" 2>/dev/null || true
pass "lockdead recovery starts a matching replacement locker first"

: >"$state/actions.log"
set +e
denied_output=$(
  QVOS_TEST_HYPRLOCK_MODE=fail \
    QVOS_TEST_CONFIRM=0 \
    run_repair 2>&1
)
denied_status=$?
set -e
((denied_status == 1)) || fail "unconfirmed lockdead clearing succeeds"
grep -Fq 'was not confirmed' <<<"$denied_output" ||
  fail "lockdead confirmation refusal"
if grep -Fq $'eval\t' "$state/actions.log"; then
  fail "unconfirmed lockdead path invokes Hyprland clear"
fi
pass "sad-face confirmation is mandatory after replacement failure"

: >"$state/actions.log"
confirmed_output=$(
  QVOS_TEST_HYPRLOCK_MODE=fail \
    QVOS_TEST_CONFIRM=1 \
    run_repair
)
grep -Fq 'official crashed-lock clearing operation' <<<"$confirmed_output" ||
  fail "confirmed lockdead result"
grep -Fq \
  $'eval\t'"$signature"$'\thl.clear_crashed_lockscreen()' \
  "$state/actions.log" ||
  fail "exact-signature official clear operation"
pass "confirmed lockdead clearing uses the exact validated signature"

: >"$state/actions.log"
env \
  HYPRLAND_INSTANCE_SIGNATURE="$signature" \
  WAYLAND_DISPLAY="$socket" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  "$locker_bin/hyprlock" 60 &
healthy_locker_pid=$!
spawned_pids+=("$healthy_locker_pid")
sleep 0.1
set +e
healthy_guard_output=$(run_repair 2>&1)
healthy_guard_status=$?
set -e
((healthy_guard_status == 1)) || fail "healthy locker recovery succeeds"
grep -Fq 'Refusing recovery: healthy matching hyprlock PID' \
  <<<"$healthy_guard_output" ||
  fail "healthy locker refusal"
if grep -Fq $'eval\t' "$state/actions.log"; then
  fail "healthy locker is cleared"
fi
kill "$healthy_locker_pid" 2>/dev/null || true
pass "a healthy exact-environment locker is never touched"

: >"$state/actions.log"
env \
  HYPRLAND_INSTANCE_SIGNATURE="$signature" \
  WAYLAND_DISPLAY="wrong-socket" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  "$locker_bin/hyprlock" 60 &
wrong_environment_locker_pid=$!
spawned_pids+=("$wrong_environment_locker_pid")
sleep 0.1
wrong_environment_output=$(run_repair --status)
grep -Fq '[Informational] hyprland.locker-unmatched' \
  <<<"$wrong_environment_output" ||
  fail "locker with mismatched Wayland environment is trusted"
if grep -Fq "[Ready        ] hyprland.locker-$signature" \
  <<<"$wrong_environment_output"; then
  fail "mismatched Wayland locker is reported healthy"
fi
kill "$wrong_environment_locker_pid" 2>/dev/null || true
pass "locker validation requires the full compositor environment"

: >"$state/actions.log"
set +e
recheck_output=$(
  QVOS_TEST_HYPRLOCK_MODE=fail \
    QVOS_TEST_CONFIRM=1 \
    QVOS_TEST_CONFIRM_SPAWN_LOCKER=1 \
    run_repair 2>&1
)
recheck_status=$?
set -e
((recheck_status == 1)) || fail "late healthy locker is cleared"
grep -Fq 'Refusing to clear: matching hyprlock PID' <<<"$recheck_output" ||
  fail "pre-clear locker recheck"
late_locker_pid=$(<"$state/confirmed-locker-pid")
spawned_pids+=("$late_locker_pid")
kill "$late_locker_pid" 2>/dev/null || true
if grep -Fq $'eval\t' "$state/actions.log"; then
  fail "late healthy locker permits clear"
fi
pass "the locker environment is revalidated immediately before clearing"

: >"$state/actions.log"
set +e
changed_instance_output=$(
  QVOS_TEST_HYPRLOCK_MODE=fail \
    QVOS_TEST_CONFIRM=1 \
    QVOS_TEST_CONFIRM_INVALIDATE_INSTANCE=1 \
    run_repair 2>&1
)
changed_instance_status=$?
set -e
((changed_instance_status == 1)) || fail "changed compositor instance is cleared"
grep -Fq 'Refusing to clear: the Hyprland instance changed during recovery.' \
  <<<"$changed_instance_output" ||
  fail "pre-clear compositor instance revalidation"
if grep -Fq $'eval\t' "$state/actions.log"; then
  fail "changed compositor instance permits clear"
fi
printf '%s\n%s\n' "$compositor_pid" "$socket" \
  >"$instance_root/hyprland.lock"
pass "the compositor instance is revalidated immediately before clearing"

: >"$state/actions.log"
printf '%s\n%s\n' "$((compositor_pid + 1))" "$socket" \
  >"$instance_root/hyprland.lock"
set +e
signature_guard_output=$(run_repair 2>&1)
signature_guard_status=$?
set -e
((signature_guard_status == 1)) || fail "invalid instance lock record succeeds"
grep -Fq 'No validated same-user Hyprland instance is available.' \
  <<<"$signature_guard_output" ||
  fail "invalid instance signature refusal"
if grep -Fq $'eval\t' "$state/actions.log"; then
  fail "invalid instance record permits clear"
fi
printf '%s\n%s\n' "$compositor_pid" "$socket" \
  >"$instance_root/hyprland.lock"
pass "PID, socket, ownership, and instance signature must agree exactly"

: >"$state/actions.log"
set +e
yes_output=$(run_repair --yes 2>&1)
yes_status=$?
set -e
((yes_status == 1)) || fail "--yes unexpectedly repaired dirty source"
grep -Fq 'Persistent repair preconditions failed' <<<"$yes_output" ||
  fail "--yes dirty-source refusal"
if grep -Fq $'eval\t' "$state/actions.log"; then
  fail "--yes invokes lockdead clearing"
fi
if rg -q 'hyprctl[[:space:]]+(--instance|-i)[[:space:]]+0' "$repair"; then
  fail "lock recovery hardcodes Hyprland instance 0"
fi
pass "--yes cannot unlock and no recovery path hardcodes instance 0"
