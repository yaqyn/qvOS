#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
system_root="$test_root/system"
test_home="$test_root/home"
test_bin="$test_root/bin"
event_log="$test_root/events"
helper="$system_root/usr/lib/qvos/first-run-root"
sudoers="$system_root/etc/sudoers.d/qvos-first-run"
marker="$test_home/.local/state/qvos/install/first-run.mode"
legacy_marker="$test_home/.local/state/omarchy/first-run.mode"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$system_root/etc/sudoers.d" "$test_home" "$test_bin"
: >"$event_log"

for command_name in ufw ufw-docker systemctl; do
  install -m 0755 /dev/stdin "$test_bin/$command_name" <<'SCRIPT'
#!/bin/bash
event="${0##*/}:$*"
printf '%s\n' "$event" >>"$QVOS_TEST_EVENT_LOG"
[[ ${QVOS_TEST_FAIL_EVENT:-} != "$event" ]]
SCRIPT
done

run_prepare() {
  HOME="$test_home" \
    OMARCHY_PATH="$root" \
    QVOS_FIRST_RUN_TESTING=1 \
    QVOS_FIRST_RUN_SYSTEM_ROOT="$system_root" \
    "$root/qvcore/install/first-run/prepare"
}

run_root() {
  QVOS_FIRST_RUN_TESTING=1 \
    QVOS_FIRST_RUN_TEST_ROOT="$system_root" \
    QVOS_FIRST_RUN_TEST_BIN="$test_bin" \
    QVOS_TEST_EVENT_LOG="$event_log" \
    "$helper" "$@"
}

printf 'legacy\n' >"$system_root/etc/sudoers.d/first-run"
printf 'reboot\n' >"$system_root/etc/sudoers.d/99-qvos-installer-reboot"
printf 'reboot\n' >"$system_root/etc/sudoers.d/99-omarchy-installer-reboot"
install -D -m 0600 /dev/null "$legacy_marker"
run_prepare

[[ -x $helper && $(stat -c '%a' "$helper") == "755" ]] ||
  fail "prepared root helper identity"
[[ -f $sudoers && $(stat -c '%a' "$sudoers") == "440" ]] ||
  fail "prepared sudoers identity"
[[ -f $marker && $(stat -c '%a' "$marker") == "600" ]] ||
  fail "prepared first-run marker identity"
[[ ! -e $legacy_marker ]] || fail "prepared first-run legacy marker cleanup"
[[ ! -e $system_root/etc/sudoers.d/first-run ]] ||
  fail "inherited broad first-run sudoers survived preparation"

desktop_user=$(id -un)
expected_sudoers=$(printf '%s\n' \
  "$desktop_user ALL=(root) NOPASSWD: /usr/lib/qvos/first-run-root apply" \
  "$desktop_user ALL=(root) NOPASSWD: /usr/lib/qvos/first-run-root cleanup")
[[ $(<"$sudoers") == "$expected_sudoers" ]] ||
  fail "first-run sudoers is not exact"
if rg -q '(systemctl|ufw|ufw-docker|gtk-update-icon-cache|/bin/rm)' \
  "$sudoers"; then
  fail "first-run sudoers exposes a general command"
fi

run_root apply
expected_apply=$(printf '%s\n' \
  'ufw:default deny incoming' \
  'ufw:default allow outgoing' \
  'ufw:allow 53317/udp' \
  'ufw:allow 53317/tcp' \
  'ufw:allow in proto udp from 172.16.0.0/12 to 172.17.0.1 port 53 comment allow-docker-dns' \
  'ufw:allow in proto udp from 192.168.0.0/16 to 172.17.0.1 port 53 comment allow-docker-dns' \
  'ufw:--force enable' \
  'systemctl:enable ufw' \
  'ufw-docker:install' \
  'ufw:reload')
[[ $(<"$event_log") == "$expected_apply" ]] ||
  fail "fixed first-run root actions"
[[ ! -e $system_root/etc/sudoers.d/99-omarchy-installer-reboot ]] ||
  fail "legacy installer reboot privilege survived root apply"
[[ ! -e $system_root/etc/sudoers.d/99-qvos-installer-reboot ]] ||
  fail "installer reboot privilege survived root apply"
[[ -L $system_root/etc/resolv.conf ]] || fail "resolver link type"
[[ $(readlink "$system_root/etc/resolv.conf") == \
  "/run/systemd/resolve/stub-resolv.conf" ]] || fail "resolver link target"
state_file="$system_root/run/qvos-first-run/root-applied"
[[ -f $state_file && $(stat -c '%a' "$state_file") == "600" ]] ||
  fail "root apply state identity"

: >"$event_log"
run_root apply
[[ ! -s $event_log ]] || fail "completed root apply repeated mutations"

printf 'legacy\n' >"$system_root/etc/sudoers.d/first-run"
run_root cleanup
[[ ! -e $helper && ! -e $sudoers &&
  ! -e $system_root/etc/sudoers.d/first-run && ! -e $state_file ]] ||
  fail "root cleanup left privilege or state"

run_prepare
mkdir -p "$system_root/run/qvos-first-run"
symlink_target="$test_root/state-target"
ln -s "$symlink_target" "$state_file"
if run_root apply >/dev/null 2>&1; then
  fail "root apply accepted a symbolic-link state"
fi
[[ ! -e $symlink_target ]] || fail "root apply followed symbolic-link state"
rm -f -- "$state_file"
rmdir "$system_root/run/qvos-first-run"

: >"$event_log"
if QVOS_TEST_FAIL_EVENT='ufw:reload' run_root apply >/dev/null 2>&1; then
  fail "root apply ignored a firewall failure"
fi
[[ ! -e $state_file ]] || fail "failed root apply recorded success"
[[ -e $helper && -e $sudoers ]] ||
  fail "failed root apply removed its retry path"
: >"$event_log"
run_root apply
run_root cleanup

unsafe_system_root="$test_root/unsafe-system"
unsafe_home="$test_root/unsafe-home"
install -d "$unsafe_system_root" "$unsafe_home/.local/state/qvos/install"
unsafe_target="$test_root/unsafe-marker-target"
ln -s "$unsafe_target" \
  "$unsafe_home/.local/state/qvos/install/first-run.mode"
if HOME="$unsafe_home" \
  OMARCHY_PATH="$root" \
  QVOS_FIRST_RUN_TESTING=1 \
  QVOS_FIRST_RUN_SYSTEM_ROOT="$unsafe_system_root" \
  "$root/qvcore/install/first-run/prepare" >/dev/null 2>&1; then
  fail "preparation accepted a symbolic-link marker"
fi
[[ ! -e $unsafe_target ]] || fail "preparation followed symbolic-link marker"
[[ ! -e $unsafe_system_root/usr/lib/qvos/first-run-root &&
  ! -e $unsafe_system_root/etc/sudoers.d/qvos-first-run ]] ||
  fail "unsafe preparation left a privilege path"

if "$root/qvcore/install/first-run/root" apply >/dev/null 2>&1; then
  fail "unprivileged root helper accepted production mode"
fi

printf 'ok - qvOS first run uses exact, retry-safe, self-cleaning root privilege\n'
