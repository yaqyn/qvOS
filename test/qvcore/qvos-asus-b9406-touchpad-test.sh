#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
system_root="$test_root/system"
test_bin="$test_root/bin"
owner="$root/qvcore/install/hardware/asus/b9406-touchpad"
quirk_file="$system_root/usr/share/libinput/99-qvos-asus-b9406-touchpad.quirks"
legacy_file="$system_root/etc/libinput/asus-expertbook-b9406.quirks"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$system_root" "$test_bin"
install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

command_name=$1
shift
arguments=("$@")
target_index=$((${#arguments[@]} - 1))
target=${arguments[$target_index]}
[[ $target == /* ]] || exit 2
arguments[$target_index]="$QVOS_TEST_SYSTEM_ROOT$target"

case $command_name in
install) exec /usr/bin/install "${arguments[@]}" ;;
rm) exec /usr/bin/rm "${arguments[@]}" ;;
*) exit 2 ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/omarchy-hw-asus-expertbook-b9406" <<'SCRIPT'
#!/bin/bash
[[ ${QVOS_TEST_ASUS_B9406:-0} == "1" ]]
SCRIPT

run_owner() {
  QVOS_TEST_SYSTEM_ROOT="$system_root" \
    PATH="$test_bin:/usr/bin" \
    bash -c 'source "$1"' _ "$owner"
}

install -D -m 0644 /dev/null "$legacy_file"
run_owner
[[ -f $legacy_file && ! -e $quirk_file ]] ||
  fail "non-ASUS hardware changed the touchpad policy"

QVOS_TEST_ASUS_B9406=1 run_owner
[[ ! -e $legacy_file ]] || fail "broken inherited libinput path cleanup"
[[ -f $quirk_file && ! -L $quirk_file ]] || fail "native libinput quirk install"
[[ $(stat -c '%a' "$quirk_file") == "644" ]] || fail "native libinput quirk mode"
grep -Fqx 'MatchBus=i2c' "$quirk_file" || fail "touchpad bus match"
grep -Fqx 'MatchVendor=0x093A' "$quirk_file" || fail "touchpad vendor match"
grep -Fqx 'MatchProduct=0x4F05' "$quirk_file" || fail "touchpad product match"
grep -Fqx 'MatchDMIModalias=dmi:*svnASUS*:pn*B9406*' "$quirk_file" ||
  fail "touchpad DMI match"
grep -Fqx 'AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE;' "$quirk_file" ||
  fail "touchpad pressure-axis correction"
if rg -q '^MatchUdevType=' "$quirk_file"; then
  fail "incorrect touchpad udev type constraint"
fi

printf 'stale\n' >"$quirk_file"
QVOS_TEST_ASUS_B9406=1 run_owner
grep -Fqx 'AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE;' "$quirk_file" ||
  fail "native quirk convergence"

[[ ! -e $root/install/config/hardware/asus/fix-asus-ptl-b9406-touchpad.sh ]] ||
  fail "broken inherited touchpad owner remains"
grep -Fqx 'install/config/hardware/asus/fix-asus-ptl-b9406-touchpad.sh' \
  "$root/qvcore/install/retired-paths" ||
  fail "broken inherited touchpad owner is not retired"
# shellcheck disable=SC2016
grep -Fqx 'source "$OMARCHY_PATH/qvcore/install/hardware/asus/b9406-touchpad"' \
  "$root/qvcore/migrations/1785755403.sh" ||
  fail "existing-system touchpad migration"

printf 'ok - ASUS B9406 touchpad quirk is native, active, exact, and update-safe\n'
