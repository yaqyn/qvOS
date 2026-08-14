#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_qvos="$test_root/qvos"
test_install="$test_qvos/qvcore/install"
test_bin="$test_root/bin"
event_log="$test_root/events"
completion_marker="$test_root/install-completed"
sudoers_root="$test_root/sudoers.d"

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
  "$test_install/post-install" \
  "$test_qvos/qvcore/branding" \
  "$test_qvos/qvcore/install/post-install" \
  "$test_qvos/qvcore/security"
install -m 0755 \
  "$root/qvcore/install/post-install/finished" \
  "$test_qvos/qvcore/install/post-install/finished"
install -m 0644 \
  "$root/qvcore/branding/terminal-art.txt" \
  "$test_qvos/qvcore/branding/terminal-art.txt"
: >"$event_log"

install -m 0755 /dev/stdin \
  "$test_qvos/qvcore/install/post-install/reboot-policy" <<'SCRIPT'
#!/bin/bash
printf 'reboot-policy\n' >>"$QVOS_TEST_EVENT_LOG"
SCRIPT

run_logged() {
  printf 'run:%s\n' "$1" >>"$QVOS_TEST_EVENT_LOG"
}
stop_install_log() {
  printf 'stop-log\n' >>"$QVOS_TEST_EVENT_LOG"
}
export -f run_logged stop_install_log

install -m 0755 /dev/stdin \
  "$test_qvos/qvcore/install/post-install/finished" <<'SCRIPT'
#!/bin/bash
printf 'finished\n' >>"$QVOS_TEST_EVENT_LOG"
SCRIPT

QVOS_TEST_EVENT_LOG="$event_log" \
QVOS_PATH="$test_qvos" \
QVOS_INSTALL="$test_install" \
  bash -c 'source "$1"' _ "$root/qvcore/install/post-install/run"

expected_run=$(
  printf 'run:%s\n' "$test_install/post-install/pacman.sh"
  printf 'run:%s\n' "$test_qvos/qvcore/security/install"
  printf 'run:%s\n' "$test_qvos/qvcore/controls/install-root"
  printf 'run:%s\n' "$test_qvos/qvcore/install/post-install/verify"
  printf 'run:%s\n' "$test_qvos/qvcore/install/post-install/reboot-policy"
  printf '%s\n' stop-log finished
)
[[ $(<"$event_log") == "$expected_run" ]] ||
  fail "post-install owner order"

policy_system_root="$test_root/reboot-policy-system"
policy_target="$policy_system_root/etc/sudoers.d/99-qvos-installer-reboot"
policy_user=$(id -un)
install -d "$policy_system_root/etc"
run_reboot_policy() {
  QVOS_REBOOT_POLICY_SYSTEM_ROOT="$policy_system_root" \
    QVOS_REBOOT_POLICY_TESTING=1 \
    QVOS_REBOOT_POLICY_USER="${QVOS_TEST_POLICY_USER:-$policy_user}" \
    "$root/qvcore/install/post-install/reboot-policy"
}

run_reboot_policy
[[ $(<"$policy_target") == \
  "$policy_user ALL=(ALL) NOPASSWD: /usr/bin/reboot" ]] ||
  fail "installer reboot policy content"
[[ $(stat -c '%u:%g:%a' -- "$policy_target") == \
  "$(id -u):$(id -g):440" ]] ||
  fail "installer reboot policy permissions"
policy_inode=$(stat -c '%i' -- "$policy_target")
run_reboot_policy
[[ $(stat -c '%i' -- "$policy_target") == "$policy_inode" ]] ||
  fail "installer reboot policy idempotence"

chmod 0640 "$policy_target"
printf 'modified policy\n' >"$policy_target"
chmod 0440 "$policy_target"
if run_reboot_policy >/dev/null 2>&1; then
  fail "modified installer reboot policy acceptance"
fi
[[ $(<"$policy_target") == "modified policy" ]] ||
  fail "modified installer reboot policy mutation"

rm -- "$policy_target"
policy_external="$test_root/reboot-policy-external"
printf 'external policy\n' >"$policy_external"
ln -s "$policy_external" "$policy_target"
if run_reboot_policy >/dev/null 2>&1; then
  fail "linked installer reboot policy acceptance"
fi
[[ $(<"$policy_external") == "external policy" ]] ||
  fail "linked installer reboot policy target mutation"

rm -- "$policy_target"
if QVOS_TEST_POLICY_USER='unsafe user' run_reboot_policy >/dev/null 2>&1; then
  fail "unsafe installer reboot policy account acceptance"
fi
[[ ! -e $policy_target && ! -L $policy_target ]] ||
  fail "unsafe account created an installer reboot policy"
printf 'ok - installer reboot privilege is validated, atomic, and idempotent\n'

install -m 0755 \
  "$root/qvcore/install/post-install/finished" \
  "$test_qvos/qvcore/install/post-install/finished"
install -m 0644 \
  "$root/qvcore/install/post-install/completion-marker" \
  "$test_qvos/qvcore/install/post-install/completion-marker"

install -m 0755 /dev/stdin "$test_bin/qvos-tui" <<'SCRIPT'
#!/bin/bash
printf 'tui:%s:%s\n' "${QVOS_TUI_FULLSCREEN:-}" "$*" >>"$QVOS_TEST_EVENT_LOG"
if [[ ${QVOS_TEST_REQUIRE_SECURE_COMPLETION:-} == "1" ]]; then
  [[ ! -e $QVOS_TEST_SUDOERS_ROOT/99-qvos-installer &&
    ! -e $QVOS_TEST_SUDOERS_ROOT/99-omarchy-installer ]] || exit 99
  cmp -s -- "$QVOS_TEST_COMPLETION_SOURCE" \
    "$QVOS_TEST_COMPLETION_MARKER" || exit 98
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$QVOS_TEST_EVENT_LOG"
if [[ ${QVOS_TEST_ENFORCE_INSTALLER_POLICY:-} == "1" &&
  ! -f $QVOS_TEST_SUDOERS_ROOT/99-qvos-installer ]]; then
  exit 97
fi

map_policy() {
  local path=$1

  [[ $path == /etc/sudoers.d/* ]] || return 1
  printf '%s/%s\n' "$QVOS_TEST_SUDOERS_ROOT" "${path##*/}"
}

case ${1:-} in
test)
  if mapped=$(map_policy "${3:-}"); then
    test "$2" "$mapped"
  else
    exec /usr/bin/test "${@:2}"
  fi
  ;;
cat)
  if mapped=$(map_policy "${3:-}"); then
    cat -- "$mapped"
  else
    exec /usr/bin/cat "${@:2}"
  fi
  ;;
rm)
  args=()
  for path in "${@:2}"; do
    if mapped=$(map_policy "$path"); then
      args+=("$mapped")
    else
      args+=("$path")
    fi
  done
  exec /usr/bin/rm "${args[@]}"
  ;;
cmp) exec /usr/bin/cmp "${@:2}" ;;
install)
  args=()
  shift
  while (($#)); do
    case $1 in
    -o | -g) shift 2 ;;
    *) args+=("$1"); shift ;;
    esac
  done
  exec /usr/bin/install "${args[@]}"
  ;;
mktemp) exec /usr/bin/mktemp "${@:2}" ;;
mv) exec /usr/bin/mv "${@:2}" ;;
stat) exec /usr/bin/stat "${@:2}" ;;
*) exit 0 ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
printf 'gum:%s\n' "$*" >>"$QVOS_TEST_EVENT_LOG"
exit "${QVOS_TEST_GUM_STATUS:-1}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/tte" <<'SCRIPT'
#!/bin/bash
input=
if [[ " $* " != *' -i '* ]]; then
  input=$(cat)
fi
printf 'tte:%s:%s\n' "$*" "$input" >>"$QVOS_TEST_EVENT_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/clear" <<'SCRIPT'
#!/bin/bash
printf 'clear\n' >>"$QVOS_TEST_EVENT_LOG"
SCRIPT

run_finished() {
  HOME="$test_root/home" \
    QVOS_PATH="$test_qvos" \
    QVOS_INSTALL_LOG_FILE="$test_root/install.log" \
    QVOS_INSTALL_COMPLETION_MARKER="$completion_marker" \
    QVOS_TEST_COMPLETION_MARKER="$completion_marker" \
    QVOS_TEST_COMPLETION_SOURCE="$test_qvos/qvcore/install/post-install/completion-marker" \
    QVOS_TEST_EVENT_LOG="$event_log" \
    QVOS_TEST_ENFORCE_INSTALLER_POLICY="${QVOS_TEST_ENFORCE_INSTALLER_POLICY:-}" \
    QVOS_TEST_REQUIRE_SECURE_COMPLETION="${QVOS_TEST_REQUIRE_SECURE_COMPLETION:-}" \
    QVOS_TEST_SUDOERS_ROOT="$sudoers_root" \
    USER="$(id -un)" \
    PATH="$test_bin:/usr/bin" \
    "$test_qvos/qvcore/install/post-install/finished"
}

install -d "$sudoers_root"
for policy in 99-qvos-installer 99-omarchy-installer; do
  printf '%s\n' \
    'root ALL=(ALL:ALL) NOPASSWD: ALL' \
    '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' \
    "$(id -un) ALL=(ALL:ALL) NOPASSWD: ALL" \
    >"$sudoers_root/$policy"
done
: >"$event_log"
QVOS_TEST_REQUIRE_SECURE_COMPLETION=1 \
QVOS_TEST_ENFORCE_INSTALLER_POLICY=1 \
QVOS_CHROOT_INSTALL=1 \
QVOS_TUI_BIN="$test_bin/qvos-tui" \
  run_finished >/dev/null
[[ -f $completion_marker ]] || fail "ISO completion marker"
cmp -s \
  "$test_qvos/qvcore/install/post-install/completion-marker" \
  "$completion_marker" || fail "ISO completion marker content"
[[ $(stat -c '%a' "$completion_marker") == "600" ]] ||
  fail "ISO completion marker mode"
[[ ! -e $sudoers_root/99-qvos-installer &&
  ! -e $sudoers_root/99-omarchy-installer ]] ||
  fail "ISO temporary installer policy cleanup"

rm -f -- "$completion_marker"
printf '%s\n' \
  'root ALL=(ALL:ALL) NOPASSWD: ALL' \
  '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' \
  "$(id -un) ALL=(ALL:ALL) NOPASSWD: ALL" \
  >"$sudoers_root/99-qvos-installer"
if QVOS_CHROOT_INSTALL=1 \
  QVOS_TUI_BIN="$test_bin/missing-qvos-tui" \
  run_finished >/dev/null 2>&1; then
  fail "ISO completion accepted a missing mandatory interface"
fi
[[ ! -e $completion_marker && -f $sudoers_root/99-qvos-installer ]] ||
  fail "missing ISO interface changed completion or authorization state"
grep -Fqx 'tui:1:--iso-finished' "$event_log" ||
  fail "ISO finished TUI"
if grep -Fq 'gum:' "$event_log"; then
  fail "ISO TUI fell through to the legacy prompt"
fi

rm -f -- "$completion_marker"
printf 'Total: 3m 12s\n' >"$test_root/install.log"
: >"$event_log"
run_finished >/dev/null
[[ ! -e $completion_marker ]] ||
  fail "declined non-ISO reboot created a completion marker"
grep -Fqx \
  "tte:-i $test_qvos/qvcore/branding/terminal-art.txt --canvas-width 0 --anchor-text c --frame-rate 920 laseretch:" \
  "$event_log" || fail "qvOS finished logo owner"
grep -Fqx \
  'tte:--canvas-width 0 --anchor-text c --frame-rate 640 print:Installed in 3m 12s' \
  "$event_log" || fail "installation duration presentation"
grep -Fq 'gum:confirm ' "$event_log" || fail "non-ISO reboot prompt"
if grep -Fq 'sudo:reboot' "$event_log"; then
  fail "declined reboot reached the system reboot command"
fi

: >"$event_log"
QVOS_TEST_GUM_STATUS=0 run_finished >/dev/null
grep -Fqx 'sudo:reboot' "$event_log" ||
  fail "accepted non-ISO reboot did not reach the system owner"

: >"$event_log"
QVOS_CHROOT_INSTALL=1 \
QVOS_TEST_GUM_STATUS=0 \
  run_finished >/dev/null
[[ -f $completion_marker ]] || fail "PATH-discovered chroot completion marker"
if grep -Fq 'sudo:reboot' "$event_log"; then
  fail "PATH-discovered chroot completion rebooted inside the target"
fi

rm -f -- "$completion_marker"
symlink_target="$test_root/symlink-target"
ln -s "$symlink_target" "$completion_marker"
printf '%s\n' \
  'root ALL=(ALL:ALL) NOPASSWD: ALL' \
  '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' \
  "$(id -un) ALL=(ALL:ALL) NOPASSWD: ALL" \
  >"$sudoers_root/99-qvos-installer"
if QVOS_CHROOT_INSTALL=1 \
  QVOS_TUI_BIN="$test_bin/qvos-tui" \
  run_finished >/dev/null 2>&1; then
  fail "ISO completion accepted a symbolic-link marker"
fi
[[ ! -e $symlink_target ]] ||
  fail "ISO completion followed a symbolic-link marker"
[[ -f $sudoers_root/99-qvos-installer ]] ||
  fail "unsafe ISO completion revoked installer authorization"

rm -f -- "$completion_marker"
for policy in 99-qvos-installer 99-omarchy-installer; do
  printf '%s\n' \
    'root ALL=(ALL:ALL) NOPASSWD: ALL' \
    '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' \
    "$(id -un) ALL=(ALL:ALL) NOPASSWD: ALL" \
    >"$sudoers_root/$policy"
done
printf 'modified legacy policy\n' >"$sudoers_root/99-omarchy-installer"
if QVOS_TEST_ENFORCE_INSTALLER_POLICY=1 \
  QVOS_CHROOT_INSTALL=1 \
  QVOS_TUI_BIN="$test_bin/qvos-tui" \
  run_finished >/dev/null 2>&1; then
  fail "modified legacy installer policy was accepted"
fi
[[ -f $sudoers_root/99-qvos-installer &&
  $(<"$sudoers_root/99-omarchy-installer") == "modified legacy policy" ]] ||
  fail "installer policy validation partially revoked authorization"
cmp -s \
  "$test_qvos/qvcore/install/post-install/completion-marker" \
  "$completion_marker" ||
  fail "failed installer cleanup did not retain its exact completion evidence"

rm -f -- "$completion_marker" "$sudoers_root/99-omarchy-installer"
printf 'modified\n' >"$sudoers_root/99-qvos-installer"
if QVOS_CHROOT_INSTALL=1 \
  QVOS_TUI_BIN="$test_bin/qvos-tui" \
  run_finished >/dev/null 2>&1; then
  fail "modified ISO installer policy was accepted"
fi
if [[ $(<"$sudoers_root/99-qvos-installer") != "modified" ]] ||
  ! cmp -s \
    "$test_qvos/qvcore/install/post-install/completion-marker" \
    "$completion_marker"; then
  fail "modified ISO policy did not preserve authorization and exact evidence"
fi

printf 'ok - qvOS singularly owns post-install order and both finished paths\n'
