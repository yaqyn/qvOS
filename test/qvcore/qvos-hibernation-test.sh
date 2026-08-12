#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
system_root="$test_root/system"
test_bin="$system_root/test-bin"
rebuild_log="$test_root/rebuild.log"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$system_root/etc/default" \
  "$system_root/etc/limine-entry-tool.d" \
  "$system_root/etc/mkinitcpio.conf.d" \
  "$system_root/etc/systemd/logind.conf.d" \
  "$system_root/etc/systemd/sleep.conf.d" \
  "$system_root/proc" \
  "$system_root/run" \
  "$system_root/sys/power" \
  "$system_root/usr/lib/qvos/power" \
  "$system_root/usr/lib/systemd/system-sleep" \
  "$test_bin"
printf 'rootfs / btrfs defaults 0 0\n' >"$system_root/etc/fstab"
cat >"$system_root/etc/default/limine" <<'CONFIG'
TARGET_OS_NAME="qvOS"
KERNEL_CMDLINE[default]+=" quiet"
KERNEL_CMDLINE[default]+=" resume=/dev/mapper/test resume_offset=123"
CONFIG
printf 'HOOKS+=(resume)\n' \
  >"$system_root/etc/mkinitcpio.conf.d/80-qvos-resume.conf"
printf 'KERNEL_CMDLINE[default]+=" resume=/dev/mapper/test resume_offset=123"\n' \
  >"$system_root/etc/limine-entry-tool.d/80-qvos-resume.conf"
printf 'foreign historical hook\n' \
  >"$system_root/etc/mkinitcpio.conf.d/omarchy_resume.conf"
printf 'foreign historical resume policy\n' \
  >"$system_root/etc/limine-entry-tool.d/resume.conf"
printf '%s\n' '[Login]' 'HandleLidSwitch=ignore' \
  >"$system_root/etc/systemd/logind.conf.d/lid.conf"
printf 'foreign sleep policy\n' \
  >"$system_root/etc/systemd/sleep.conf.d/hibernate.conf"
printf '4096\n' >"$system_root/sys/power/image_size"
printf 's2idle [deep]\n' >"$system_root/sys/power/mem_sleep"
printf 'MemTotal:        8192 kB\n' >"$system_root/proc/meminfo"
printf '%s\n' 'Filename Type Size Used Priority' >"$system_root/proc/swaps"

install -m 0755 /dev/stdin "$test_bin/btrfs" <<'SCRIPT'
#!/bin/bash
case $1:$2 in
subvolume:show)
  [[ -d $3 ]]
  ;;
subvolume:create)
  mkdir "$3"
  ;;
subvolume:delete)
  rmdir "$3"
  ;;
filesystem:mkswapfile)
  install -m 0600 /dev/null "${@: -1}"
  ;;
inspect-internal:map-swapfile)
  printf '%s\n' "${QVOS_TEST_OFFSET:-123}"
  ;;
*) exit 2 ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/chattr" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/findmnt" <<'SCRIPT'
#!/bin/bash
case $* in
"-n -o FSTYPE -T "*) printf 'btrfs\n' ;;
"-n -o SOURCE -T "*) printf '/dev/mapper/test[/@]\n' ;;
*) exit 2 ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/limine-mkinitcpio" <<'SCRIPT'
#!/bin/bash
printf 'rebuild\n' >>"$QVOS_TEST_REBUILD_LOG"
[[ ${QVOS_TEST_REBUILD_FAIL:-0} != "1" ]]
SCRIPT
install -m 0755 /dev/stdin "$test_bin/swapon" <<'SCRIPT'
#!/bin/bash
swap_file=${@: -1}
grep -Fq "$swap_file " "$QVOS_TEST_SYSTEM_ROOT/proc/swaps" ||
  printf '%s file 8192 0 0\n' "$swap_file" >>"$QVOS_TEST_SYSTEM_ROOT/proc/swaps"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/swapoff" <<'SCRIPT'
#!/bin/bash
swap_file=$1
temporary=$(mktemp "$QVOS_TEST_SYSTEM_ROOT/proc/.swaps.XXXXXX")
awk -v target="$swap_file" '$1 != target { print }' \
  "$QVOS_TEST_SYSTEM_ROOT/proc/swaps" >"$temporary"
mv "$temporary" "$QVOS_TEST_SYSTEM_ROOT/proc/swaps"
SCRIPT

hibernation_env=(
  "QVOS_PATH=$root"
  QVOS_HIBERNATION_TESTING=1
  "QVOS_HIBERNATION_SYSTEM_ROOT=$system_root"
  "QVOS_HIBERNATION_TEST_BIN=$test_bin"
  "QVOS_TEST_REBUILD_LOG=$rebuild_log"
  "QVOS_TEST_SYSTEM_ROOT=$system_root"
)

fresh_system_root="$test_root/fresh-system"
cp -a -- "$system_root" "$fresh_system_root"
rm -- \
  "$fresh_system_root/etc/default/limine" \
  "$fresh_system_root/etc/mkinitcpio.conf.d/80-qvos-resume.conf" \
  "$fresh_system_root/etc/mkinitcpio.conf.d/omarchy_resume.conf" \
  "$fresh_system_root/etc/limine-entry-tool.d/80-qvos-resume.conf" \
  "$fresh_system_root/etc/limine-entry-tool.d/resume.conf"
fresh_hibernation_env=(
  "QVOS_PATH=$root"
  QVOS_HIBERNATION_TESTING=1
  "QVOS_HIBERNATION_SYSTEM_ROOT=$fresh_system_root"
  "QVOS_HIBERNATION_TEST_BIN=$fresh_system_root/test-bin"
  "QVOS_TEST_REBUILD_LOG=$test_root/fresh-rebuild.log"
  "QVOS_TEST_SYSTEM_ROOT=$fresh_system_root"
)
env "${fresh_hibernation_env[@]}" \
  "$root/qvcore/power/hibernation/setup" --force --no-rebuild >/dev/null
[[ ! -e $fresh_system_root/etc/default/limine &&
  ! -L $fresh_system_root/etc/default/limine ]] ||
  fail "fresh hibernation created a duplicate Limine defaults owner"
grep -Fqx \
  'KERNEL_CMDLINE[default]+=" resume=/dev/mapper/test resume_offset=123"' \
  "$fresh_system_root/etc/limine-entry-tool.d/80-qvos-resume.conf" ||
  fail "fresh hibernation without Limine defaults"
printf 'ok - fresh hibernation precedes the singular Limine defaults owner\n'

env "${hibernation_env[@]}" \
  "$root/qvcore/power/hibernation/setup" --force

grep -Fqx 'HOOKS+=(resume)' \
  "$system_root/etc/mkinitcpio.conf.d/80-qvos-resume.conf" ||
  fail "native mkinitcpio resume hook"
grep -Fqx 'KERNEL_CMDLINE[default]+=" resume=/dev/mapper/test resume_offset=123"' \
  "$system_root/etc/limine-entry-tool.d/80-qvos-resume.conf" ||
  fail "native Limine resume policy"
grep -Fqx '/swap/swapfile none swap defaults,pri=0 0 0' \
  "$system_root/etc/fstab" || fail "native hibernation fstab entry"
grep -Fqx 'TARGET_OS_NAME="qvOS"' "$system_root/etc/default/limine" ||
  fail "unrelated Limine policy preservation"
if grep -Fq 'resume=' "$system_root/etc/default/limine"; then
  fail "duplicate Limine resume policy"
fi
[[ $(<"$system_root/etc/mkinitcpio.conf.d/omarchy_resume.conf") == \
  "foreign historical hook" ]] || fail "historical hook preservation"
[[ $(<"$system_root/etc/limine-entry-tool.d/resume.conf") == \
  "foreign historical resume policy" ]] ||
  fail "historical resume policy preservation"
grep -Fqx 'HandleLidSwitch=ignore' \
  "$system_root/etc/systemd/logind.conf.d/lid.conf" ||
  fail "unrelated logind policy preservation"
grep -Fqx 'foreign sleep policy' \
  "$system_root/etc/systemd/sleep.conf.d/hibernate.conf" ||
  fail "unrelated sleep policy preservation"
keyboard="$system_root/usr/lib/systemd/system-sleep/qvos-keyboard-backlight"
[[ -x $keyboard && $(stat -c '%a' "$keyboard") == "755" ]] ||
  fail "root-owned executable keyboard sleep helper"
env "${hibernation_env[@]}" \
  "$root/qvcore/power/hibernation/available" ||
  fail "native hibernation availability"
[[ $(<"$rebuild_log") == "rebuild" ]] || fail "single hibernation rebuild"
printf 'ok - hibernation updates only singular native boot policy\n'

state_before=$(find "$system_root/etc" "$system_root/swap" \
  -type f -printf '%p|%m|' -exec sha256sum {} \; | sort)
env "${hibernation_env[@]}" \
  "$root/qvcore/power/hibernation/setup" --force --no-rebuild >/dev/null
state_after=$(find "$system_root/etc" "$system_root/swap" \
  -type f -printf '%p|%m|' -exec sha256sum {} \; | sort)
[[ $state_after == "$state_before" ]] || fail "idempotent hibernation setup"
[[ $(<"$rebuild_log") == "rebuild" ]] || fail "idempotent rebuild suppression"

resume_policy="$system_root/etc/limine-entry-tool.d/80-qvos-resume.conf"
resume_before=$(sha256sum "$resume_policy")
set +e
env "${hibernation_env[@]}" \
  QVOS_TEST_OFFSET=456 \
  QVOS_TEST_REBUILD_FAIL=1 \
  "$root/qvcore/power/hibernation/setup" --force >/dev/null 2>&1
failed_status=$?
set -e
((failed_status == 1)) || fail "failed hibernation rebuild status"
[[ $(sha256sum "$resume_policy") == "$resume_before" ]] ||
  fail "failed hibernation rebuild rollback"
grep -Fqx 'KERNEL_CMDLINE[default]+=" resume=/dev/mapper/test resume_offset=123"' \
  "$resume_policy" || fail "restored hibernation resume policy"
printf 'ok - failed hibernation rebuild restores the prior boot policy\n'

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
exit "${QVOS_TEST_CONFIRM_STATUS:-0}"
SCRIPT
set +e
env "${hibernation_env[@]}" QVOS_TEST_CONFIRM_STATUS=1 \
  PATH="$test_bin:/usr/bin" "$root/qvcore/power/hibernation/remove" \
  >/dev/null 2>&1
cancel_status=$?
set -e
((cancel_status == 130)) || fail "hibernation removal cancellation status"
[[ -f $system_root/swap/swapfile ]] || fail "cancelled hibernation storage"

env "${hibernation_env[@]}" QVOS_TEST_CONFIRM_STATUS=0 \
  PATH="$test_bin:/usr/bin" "$root/qvcore/power/hibernation/remove" >/dev/null
[[ ! -e $system_root/swap && ! -L $system_root/swap ]] ||
  fail "removed hibernation storage"
for managed in \
  "$system_root/etc/mkinitcpio.conf.d/80-qvos-resume.conf" \
  "$system_root/etc/limine-entry-tool.d/80-qvos-resume.conf" \
  "$system_root/etc/limine-entry-tool.d/80-qvos-rtc-alarm.conf"; do
  [[ ! -e $managed && ! -L $managed ]] || fail "removed hibernation boot policy"
done
[[ $(<"$system_root/etc/mkinitcpio.conf.d/omarchy_resume.conf") == \
  "foreign historical hook" ]] || fail "historical hook removal side effect"
[[ $(<"$system_root/etc/limine-entry-tool.d/resume.conf") == \
  "foreign historical resume policy" ]] ||
  fail "historical resume removal side effect"
! env "${hibernation_env[@]}" \
  "$root/qvcore/power/hibernation/available" ||
  fail "removed hibernation remained available"
grep -Fqx 'rootfs / btrfs defaults 0 0' "$system_root/etc/fstab" ||
  fail "hibernation removal fstab preservation"
printf 'ok - hibernation removal confirms, rebuilds, and deletes only owned storage\n'

for invalid in unexpected '--force --force' '--no-rebuild --no-rebuild'; do
  read -r -a invalid_args <<<"$invalid"
  if env "${hibernation_env[@]}" \
    "$root/qvcore/power/hibernation/setup" "${invalid_args[@]}" \
    >/dev/null 2>&1; then
    fail "invalid hibernation setup arguments: $invalid"
  fi
done
if env "${hibernation_env[@]}" \
  "$root/qvcore/power/hibernation/remove" unexpected >/dev/null 2>&1; then
  fail "invalid hibernation remove arguments"
fi
printf 'ok - hibernation public owners reject ambiguous arguments before mutation\n'

foreign_resume="$system_root/etc/limine-entry-tool.d/80-qvos-resume.conf"
printf 'foreign native resume policy\n' >"$foreign_resume"
set +e
env "${hibernation_env[@]}" \
  "$root/qvcore/power/hibernation/setup" --force --no-rebuild \
  >/dev/null 2>&1
foreign_status=$?
set -e
((foreign_status == 1)) || fail "foreign native policy rejection status"
grep -Fqx 'foreign native resume policy' "$foreign_resume" ||
  fail "foreign native policy preservation"
[[ ! -e $system_root/swap && ! -L $system_root/swap ]] ||
  fail "foreign native policy preflight created storage"
printf 'ok - modified native hibernation policy fails before any mutation\n'

rm -- "$foreign_resume"
chmod 0664 "$system_root/etc/fstab"
set +e
env "${hibernation_env[@]}" \
  "$root/qvcore/power/hibernation/setup" --force --no-rebuild \
  >/dev/null 2>&1
unsafe_mode_status=$?
set -e
((unsafe_mode_status == 1)) || fail "writable system policy rejection status"
[[ ! -e $system_root/swap && ! -L $system_root/swap ]] ||
  fail "writable system policy preflight created storage"
chmod 0644 "$system_root/etc/fstab"
printf 'ok - writable hibernation system policy fails before mutation\n'

root_helper="$system_root/usr/lib/qvos/power/hibernation"
outside_helper="$test_root/outside-helper"
printf 'preserve\n' >"$outside_helper"
rm -- "$root_helper"
ln -s "$outside_helper" "$root_helper"
if env "${hibernation_env[@]}" \
  "$root/qvcore/power/hibernation/install-root" >/dev/null 2>&1; then
  fail "linked root hibernation helper was accepted"
fi
grep -Fqx 'preserve' "$outside_helper" || fail "linked helper target changed"
printf 'ok - root helper installation refuses links and foreign targets\n'
