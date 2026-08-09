#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_root=$(mktemp -d)
test_bin="$test_root/bin"
event_log="$test_root/events.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d -m 0755 "$test_bin"
install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf 'systemctl|%s\n' "$*" >>"$QVOS_TEST_POLICY_LOG"
[[ ${QVOS_TEST_SYSTEMCTL_FAIL:-} != "1" ]]
SCRIPT
install -m 0755 /dev/stdin "$test_bin/gpgconf" <<'SCRIPT'
#!/bin/bash
printf 'gpgconf|%s\n' "$*" >>"$QVOS_TEST_POLICY_LOG"
true
SCRIPT

prepare_policy_root() {
  local fixture=$1

  install -d -m 0755 \
    "$fixture/etc/gnupg" \
    "$fixture/etc/systemd/system.conf.d" \
    "$fixture/etc/systemd/system/user@.service.d"
}

write_gpg_policy() {
  local fixture=$1

  install -m 0644 /dev/stdin "$fixture/etc/gnupg/dirmngr.conf" <<'EOF'
keyserver hkps://keyserver.ubuntu.com
keyserver hkps://pgp.surfnet.nl
keyserver hkps://keys.mailvelope.com
keyserver hkps://keyring.debian.org
keyserver hkps://pgp.mit.edu

connect-quick-timeout 4
EOF
}

write_systemd_policies() {
  local fixture=$1

  install -m 0644 /dev/stdin \
    "$fixture/etc/systemd/system.conf.d/10-faster-shutdown.conf" <<'EOF'
[Manager]
DefaultTimeoutStopSec=5s
EOF
  install -m 0644 /dev/stdin \
    "$fixture/etc/systemd/system/user@.service.d/faster-shutdown.conf" <<'EOF'
[Service]
TimeoutStopSec=5s
EOF
}

run_owner() {
  local fixture=$1
  shift

  QVOS_INSTALL_POLICY_TESTING=1 \
  QVOS_INSTALL_POLICY_SYSTEM_ROOT="$fixture" \
  QVOS_INSTALL_SYSTEMCTL="$test_bin/systemctl" \
  QVOS_INSTALL_GPGCONF="$test_bin/gpgconf" \
  QVOS_TEST_POLICY_LOG="$event_log" \
    "$@"
}

exact_root="$test_root/exact"
prepare_policy_root "$exact_root"
write_gpg_policy "$exact_root"
write_systemd_policies "$exact_root"
: >"$event_log"
run_owner "$exact_root" "$root/qvcore/install/retire-inherited-system-policy"
for retired in \
  etc/gnupg/dirmngr.conf \
  etc/systemd/system.conf.d/10-faster-shutdown.conf \
  etc/systemd/system/user@.service.d/faster-shutdown.conf; do
  [[ ! -e $exact_root/$retired && ! -L $exact_root/$retired ]] ||
    fail "exact inherited policy remains: $retired"
done
[[ $(<"$event_log") == $'gpgconf|--kill dirmngr\nsystemctl|daemon-reload' ]] ||
  fail "exact inherited policy retirement activation"
event_snapshot=$(<"$event_log")
run_owner "$exact_root" "$root/qvcore/install/retire-inherited-system-policy"
[[ $(<"$event_log") == "$event_snapshot" ]] ||
  fail "idempotent inherited policy retirement"

preserve_root="$test_root/preserve"
prepare_policy_root "$preserve_root"
printf 'custom GnuPG policy\n' >"$preserve_root/etc/gnupg/dirmngr.conf"
outside="$test_root/outside-policy"
printf 'outside\n' >"$outside"
ln -s "$outside" \
  "$preserve_root/etc/systemd/system.conf.d/10-faster-shutdown.conf"
install -m 0644 /dev/stdin \
  "$preserve_root/etc/systemd/system/user@.service.d/faster-shutdown.conf" <<'EOF'
[Service]
TimeoutStopSec=5s
EOF
: >"$event_log"
run_owner "$preserve_root" \
  "$root/qvcore/install/retire-inherited-system-policy" >/dev/null 2>&1
[[ $(<"$preserve_root/etc/gnupg/dirmngr.conf") == "custom GnuPG policy" ]] ||
  fail "modified GnuPG policy preservation"
[[ -L $preserve_root/etc/systemd/system.conf.d/10-faster-shutdown.conf &&
  $(<"$outside") == "outside" ]] || fail "linked system policy preservation"
[[ ! -e $preserve_root/etc/systemd/system/user@.service.d/faster-shutdown.conf ]] ||
  fail "exact policy was hidden by a modified sibling"
[[ $(<"$event_log") == "systemctl|daemon-reload" ]] ||
  fail "preserved policy triggered an unrelated command"

rollback_root="$test_root/rollback"
prepare_policy_root "$rollback_root"
write_systemd_policies "$rollback_root"
: >"$event_log"
if QVOS_TEST_SYSTEMCTL_FAIL=1 \
  run_owner "$rollback_root" \
    "$root/qvcore/install/retire-inherited-system-policy" >/dev/null 2>&1; then
  fail "systemd reload failure was hidden"
fi
write_systemd_policies "$exact_root"
for relative in \
  etc/systemd/system.conf.d/10-faster-shutdown.conf \
  etc/systemd/system/user@.service.d/faster-shutdown.conf; do
  cmp -s "$rollback_root/$relative" "$exact_root/$relative" ||
    fail "systemd reload failure did not restore $relative"
  [[ ! -e $rollback_root/$relative.qvos-retirement-backup ]] ||
    fail "systemd rollback left a transaction artifact"
done
[[ $(grep -Fxc 'systemctl|daemon-reload' "$event_log") == "2" ]] ||
  fail "systemd rollback did not reload restored policy"

recovery_root="$test_root/recovery"
prepare_policy_root "$recovery_root"
install -m 0644 /dev/stdin \
  "$recovery_root/etc/systemd/system.conf.d/10-faster-shutdown.conf.qvos-retirement-backup" <<'EOF'
[Manager]
DefaultTimeoutStopSec=5s
EOF
: >"$event_log"
run_owner "$recovery_root" "$root/qvcore/install/retire-inherited-system-policy"
[[ ! -e $recovery_root/etc/systemd/system.conf.d/10-faster-shutdown.conf.qvos-retirement-backup ]] ||
  fail "interrupted systemd retirement was not recovered"
[[ $(<"$event_log") == "systemctl|daemon-reload" ]] ||
  fail "recovered systemd retirement was not loaded"

unsafe_root="$test_root/unsafe"
prepare_policy_root "$unsafe_root"
write_gpg_policy "$unsafe_root"
chmod 0777 "$unsafe_root"
gpg_before=$(sha256sum "$unsafe_root/etc/gnupg/dirmngr.conf")
if run_owner "$unsafe_root" \
  "$root/qvcore/install/retire-inherited-system-policy" >/dev/null 2>&1; then
  fail "world-writable fixture root was accepted"
fi
[[ $(sha256sum "$unsafe_root/etc/gnupg/dirmngr.conf") == "$gpg_before" ]] ||
  fail "unsafe fixture root was mutated"

"$root/qvcore/install/check" >/dev/null
"$root/qvcore/power/check" >/dev/null
"$root/qvcore/migrations/check" >/dev/null

printf 'ok - inherited global policy retires exactly with rollback and preservation\n'
