#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
owner="$root/qvcore/install/hardware/asus/b9406-touchpad"
source_file="$root/qvcore/install/hardware/asus/b9406-touchpad.quirks"
test_root=$(mktemp -d)
system_root="$test_root/system"
test_bin="$test_root/bin"
target="$system_root/usr/share/libinput/99-qvos-asus-b9406-touchpad.quirks"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$system_root/sys/class/dmi/id" "$test_bin"
install -m 0755 /dev/stdin "$test_bin/qv-cmd-present" <<'SCRIPT'
#!/bin/bash
[[ $# == 1 && $1 == "lspci" ]]
SCRIPT
install -m 0755 /dev/stdin "$test_bin/lspci" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "${QVOS_TEST_LSPCI:-}"
SCRIPT

run_owner() {
  QVOS_PATH="$root" \
  QVOS_INSTALL_HARDWARE_TESTING=1 \
  QVOS_INSTALL_HARDWARE_SYSTEM_ROOT="$system_root" \
  QVOS_HARDWARE_TESTING=1 \
  QVOS_HARDWARE_FIXTURE_ROOT="$system_root" \
  QVOS_TEST_LSPCI="${QVOS_TEST_LSPCI:-}" \
  PATH="$test_bin:/usr/bin" \
    bash -euc 'source "$1"' _ "$owner"
}

printf 'Other Vendor\n' >"$system_root/sys/class/dmi/id/sys_vendor"
printf 'ExpertBook B9406\n' >"$system_root/sys/class/dmi/id/product_name"
QVOS_TEST_LSPCI='00:02.0 VGA compatible controller: Intel Panther Lake Graphics' \
  run_owner
[[ ! -e $target ]] || fail "non-ASUS hardware changed the touchpad policy"

printf 'ASUSTeK COMPUTER INC.\n' >"$system_root/sys/class/dmi/id/sys_vendor"
QVOS_TEST_LSPCI='00:02.0 VGA compatible controller: Intel Panther Lake Graphics' \
  run_owner
cmp -s "$source_file" "$target" || fail "native libinput quirk install"
[[ $(stat -c '%a' "$target") == "644" ]] || fail "native libinput quirk mode"
grep -Fqx 'MatchBus=i2c' "$target" || fail "touchpad bus match"
grep -Fqx 'MatchVendor=0x093A' "$target" || fail "touchpad vendor match"
grep -Fqx 'MatchProduct=0x4F05' "$target" || fail "touchpad product match"
grep -Fqx 'MatchDMIModalias=dmi:*svnASUS*:pn*B9406*' "$target" ||
  fail "touchpad DMI match"
grep -Fqx 'AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE;' "$target" ||
  fail "touchpad pressure-axis correction"
if rg -q '^MatchUdevType=' "$target"; then
  fail "incorrect touchpad udev type constraint"
fi

inode=$(stat -c '%i' "$target")
QVOS_TEST_LSPCI='00:02.0 VGA compatible controller: Intel Panther Lake Graphics' \
  run_owner
[[ $(stat -c '%i' "$target") == "$inode" ]] || fail "idempotent quirk install"

printf 'administrator quirk\n' >"$target"
if QVOS_TEST_LSPCI='00:02.0 VGA compatible controller: Intel Panther Lake Graphics' \
  run_owner >/dev/null 2>&1; then
  fail "modified native touchpad policy was accepted"
fi
[[ $(<"$target") == "administrator quirk" ]] ||
  fail "modified native touchpad policy was replaced"

[[ ! -e $root/install && ! -L $root/install ]] ||
  fail "inherited install tree remains"
printf 'ok - ASUS B9406 touchpad quirk is native, exact, and preservation-safe\n'
