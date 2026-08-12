#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
owner="$root/qvcore/install/system-tuning"
nofile_source="$root/qvcore/install/system/nofile.conf"
watchers_source="$root/qvcore/install/system/file-watchers.conf"
network_source="$root/qvcore/install/system/network.conf"
plocate_source="$root/qvcore/install/system/plocate-ac-only.conf"
power_key_source="$root/qvcore/install/system/power-key.conf"
test_root=$(mktemp -d)
test_bin="$test_root/bin"
sysctl_log="$test_root/sysctl.log"
systemctl_log="$test_root/systemctl.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/sysctl" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_SYSCTL_LOG"
[[ ${QVOS_TEST_SYSCTL_FAIL:-0} != "1" ]]
SCRIPT
install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_SYSTEMCTL_LOG"
[[ ${QVOS_TEST_SYSTEMCTL_FAIL:-0} != "1" ]]
SCRIPT

run_owner() {
  local fixture=$1
  shift

  QVOS_PATH="$root" \
  QVOS_INSTALL_SYSTEM_TESTING=1 \
  QVOS_INSTALL_SYSTEM_ROOT="$fixture" \
  QVOS_INSTALL_SYSCTL="$test_bin/sysctl" \
  QVOS_INSTALL_SYSTEMCTL="$test_bin/systemctl" \
  QVOS_TEST_SYSCTL_LOG="$sysctl_log" \
  QVOS_TEST_SYSTEMCTL_LOG="$systemctl_log" \
    "$owner" "$@"
}

exact_root="$test_root/exact"
install -d "$exact_root"
: >"$sysctl_log"
: >"$systemctl_log"
run_owner "$exact_root" all

for target in \
  etc/systemd/system.conf.d/99-qvos-nofile.conf \
  etc/systemd/user.conf.d/99-qvos-nofile.conf; do
  cmp -s "$nofile_source" "$exact_root/$target" ||
    fail "native NOFILE policy: $target"
  [[ $(stat -c '%a' "$exact_root/$target") == "644" ]] ||
    fail "native NOFILE policy mode: $target"
done
cmp -s "$watchers_source" \
  "$exact_root/etc/sysctl.d/90-qvos-file-watchers.conf" ||
  fail "native file-watcher policy"
expected_sysctl_log=$(printf '%s\n%s' \
  "-q -p $exact_root/etc/sysctl.d/90-qvos-file-watchers.conf" \
  "-q -p $exact_root/etc/sysctl.d/90-qvos-network.conf")
[[ $(<"$sysctl_log") == "$expected_sysctl_log" ]] ||
  fail "sysctl policies apply only their native sources"
cmp -s "$network_source" \
  "$exact_root/etc/sysctl.d/90-qvos-network.conf" ||
  fail "native network policy"
cmp -s "$plocate_source" \
  "$exact_root/etc/systemd/system/plocate-updatedb.service.d/50-qvos-ac-only.conf" ||
  fail "native plocate power policy"
[[ $(<"$systemctl_log") == "daemon-reload" ]] ||
  fail "native plocate policy reload"
cmp -s "$power_key_source" \
  "$exact_root/etc/systemd/logind.conf.d/50-qvos-power-key.conf" ||
  fail "native power-key policy"

state_before=$(find "$exact_root/etc" -type f -printf '%P|%m|%i|%T@\n' | sort)
run_owner "$exact_root" all
[[ $(find "$exact_root/etc" -type f -printf '%P|%m|%i|%T@\n' | sort) == \
  "$state_before" ]] || fail "idempotent system-tuning reconciliation"
[[ $(wc -l <"$sysctl_log") == 4 ]] ||
  fail "idempotent sysctl readback"
[[ $(wc -l <"$systemctl_log") == 1 ]] ||
  fail "idempotent plocate policy reload"

chroot_root="$test_root/chroot"
install -d "$chroot_root"
: >"$sysctl_log"
: >"$systemctl_log"
QVOS_CHROOT_INSTALL=1 run_owner "$chroot_root" all
cmp -s "$watchers_source" \
  "$chroot_root/etc/sysctl.d/90-qvos-file-watchers.conf" ||
  fail "target-chroot file-watcher policy"
cmp -s "$network_source" \
  "$chroot_root/etc/sysctl.d/90-qvos-network.conf" ||
  fail "target-chroot network policy"
cmp -s "$plocate_source" \
  "$chroot_root/etc/systemd/system/plocate-updatedb.service.d/50-qvos-ac-only.conf" ||
  fail "target-chroot plocate power policy"
[[ ! -s $sysctl_log && ! -s $systemctl_log ]] ||
  fail "target-chroot tuning changed the builder runtime"
if QVOS_CHROOT_INSTALL=invalid run_owner "$test_root/invalid-chroot" all \
  >/dev/null 2>&1; then
  fail "invalid chroot signal was accepted"
fi

preserve_root="$test_root/preserve"
install -d \
  "$preserve_root/etc/systemd/system.conf.d" \
  "$preserve_root/etc/systemd/user.conf.d" \
  "$preserve_root/etc/systemd/logind.conf.d" \
  "$preserve_root/etc/sysctl.d"
printf 'custom NOFILE policy\n' \
  >"$preserve_root/etc/systemd/system.conf.d/99-qvos-nofile.conf"
printf 'fs.inotify.max_user_watches=42\n' \
  >"$preserve_root/etc/sysctl.d/90-qvos-file-watchers.conf"
printf 'custom power key policy\n' \
  >"$preserve_root/etc/systemd/logind.conf.d/50-qvos-power-key.conf"
: >"$sysctl_log"
if run_owner "$preserve_root" all >/dev/null 2>&1; then
  fail "modified native system tuning was accepted"
fi
[[ $(<"$preserve_root/etc/systemd/system.conf.d/99-qvos-nofile.conf") == \
  "custom NOFILE policy" && \
  $(<"$preserve_root/etc/sysctl.d/90-qvos-file-watchers.conf") == \
  "fs.inotify.max_user_watches=42" && \
  $(<"$preserve_root/etc/systemd/logind.conf.d/50-qvos-power-key.conf") == \
  "custom power key policy" ]] ||
  fail "modified native system tuning was changed"
[[ ! -s $sysctl_log ]] ||
  fail "modified native file-watcher policy was applied"

linked_root="$test_root/linked"
outside="$test_root/outside-nofile"
install -d "$linked_root/etc/systemd/system.conf.d" \
  "$linked_root/etc/systemd/user.conf.d"
printf 'outside\n' >"$outside"
ln -s "$outside" \
  "$linked_root/etc/systemd/system.conf.d/99-qvos-nofile.conf"
if run_owner "$linked_root" nofile >/dev/null 2>&1; then
  fail "linked native system-tuning target was accepted"
fi
[[ $(<"$outside") == "outside" ]] ||
  fail "linked native system-tuning target was followed"

rollback_root="$test_root/rollback"
install -d "$rollback_root/etc/sysctl.d"
if QVOS_TEST_SYSCTL_FAIL=1 \
  run_owner "$rollback_root" file-watchers >/dev/null 2>&1; then
  fail "file-watcher activation failure was hidden"
fi
[[ ! -e $rollback_root/etc/sysctl.d/90-qvos-file-watchers.conf ]] ||
  fail "file-watcher activation failure did not roll back"

existing_root="$test_root/existing"
install -d "$existing_root/etc/sysctl.d"
install -m 0644 "$watchers_source" \
  "$existing_root/etc/sysctl.d/90-qvos-file-watchers.conf"
if QVOS_TEST_SYSCTL_FAIL=1 \
  run_owner "$existing_root" file-watchers >/dev/null 2>&1; then
  fail "existing file-watcher activation failure was hidden"
fi
cmp -s "$watchers_source" \
  "$existing_root/etc/sysctl.d/90-qvos-file-watchers.conf" ||
  fail "existing native file-watcher policy was rolled back"

modified_root="$test_root/modified"
install -d \
  "$modified_root/etc/sysctl.d" \
  "$modified_root/etc/systemd/system/plocate-updatedb.service.d"
printf 'net.ipv4.tcp_mtu_probing=0\n' \
  >"$modified_root/etc/sysctl.d/90-qvos-network.conf"
printf '[Unit]\nConditionACPower=false\n' \
  >"$modified_root/etc/systemd/system/plocate-updatedb.service.d/50-qvos-ac-only.conf"
for operation in network plocate; do
  if run_owner "$modified_root" "$operation" >/dev/null 2>&1; then
    fail "modified native $operation policy was accepted"
  fi
done
[[ $(<"$modified_root/etc/sysctl.d/90-qvos-network.conf") == \
  "net.ipv4.tcp_mtu_probing=0" ]] ||
  fail "modified native network policy was changed"
grep -Fqx 'ConditionACPower=false' \
  "$modified_root/etc/systemd/system/plocate-updatedb.service.d/50-qvos-ac-only.conf" ||
  fail "modified native plocate policy was changed"

network_rollback_root="$test_root/network-rollback"
install -d "$network_rollback_root/etc/sysctl.d"
if QVOS_TEST_SYSCTL_FAIL=1 \
  run_owner "$network_rollback_root" network >/dev/null 2>&1; then
  fail "network policy activation failure was hidden"
fi
[[ ! -e $network_rollback_root/etc/sysctl.d/90-qvos-network.conf ]] ||
  fail "network policy activation failure did not roll back"

plocate_rollback_root="$test_root/plocate-rollback"
install -d "$plocate_rollback_root"
: >"$systemctl_log"
if QVOS_TEST_SYSTEMCTL_FAIL=1 \
  run_owner "$plocate_rollback_root" plocate >/dev/null 2>&1; then
  fail "plocate policy activation failure was hidden"
fi
[[ ! -e $plocate_rollback_root/etc/systemd/system/plocate-updatedb.service.d/50-qvos-ac-only.conf ]] ||
  fail "plocate policy activation failure did not roll back"
[[ $(wc -l <"$systemctl_log") == 2 ]] ||
  fail "plocate policy rollback did not refresh the manager"

if rg -n '99-omarchy-nofile|90-omarchy-file-watchers|99-sysctl\.conf|plocate-updatedb\.service\.d/ac-only\.conf' \
  "$root/qvcore/install" --glob '!AGENTS.md' --glob '!check'; then
  fail "active installer system tuning remains inherited"
fi
if rg -n 'HandlePowerKey=.*ignore|disable-usb-autosuspend|usbcore autosuspend=-1' \
  "$root/qvcore/install/config" --glob '!power-key.sh'; then
  fail "fresh install retains a direct or global inherited power policy"
fi

unsafe_root="$test_root/unsafe"
install -d "$unsafe_root"
chmod 0777 "$unsafe_root"
if run_owner "$unsafe_root" all >/dev/null 2>&1; then
  fail "world-writable system-tuning root was accepted"
fi

"$root/qvcore/install/check" >/dev/null
"$root/qvcore/migrations/check" >/dev/null
printf 'ok - qvOS system tuning is native, atomic, exact, and preservation-safe\n'
