#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_root=$(mktemp -d)
test_bin="$test_root/bin"
cryptsetup_log="$test_root/cryptsetup.log"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/lsblk" <<'SCRIPT'
#!/bin/bash
flags=""
field=""
device=""
while (($# > 0)); do
  case $1 in
  -o)
    field=${2:-}
    shift 2
    ;;
  --)
    shift
    device=${1:-}
    break
    ;;
  *)
    flags+=" $1"
    shift
    ;;
  esac
done

case $field in
NAME,FSTYPE)
  if [[ ${QVOS_TEST_NO_LUKS:-0} == "1" ]]; then
    printf '/dev/qvos-test-disk0 ext4\n'
  else
    printf '/dev/qvos-test-a crypto_LUKS\n'
    printf '/dev/qvos-test-b crypto_LUKS\n'
  fi
  ;;
NAME,TYPE)
  printf '/dev/qvos-test-disk0 disk\n'
  ;;
TYPE,FSTYPE,MOUNTPOINT)
  [[ $device == "/dev/qvos-test-disk0" ]] || exit 2
  printf 'disk\npart ext4 /\npart\n'
  ;;
TYPE)
  case $device in
  /dev/qvos-test-disk0) printf 'disk\n' ;;
  /dev/qvos-test-a | /dev/qvos-test-b) printf 'part\n' ;;
  *) exit 32 ;;
  esac
  ;;
PKNAME)
  case $device in
  /dev/qvos-test-a | /dev/qvos-test-b) printf 'qvos-test-disk0\n' ;;
  /dev/qvos-test-disk0) ;;
  *) exit 32 ;;
  esac
  ;;
SIZE)
  case $device in
  /dev/qvos-test-a) printf '100G\n' ;;
  /dev/qvos-test-b) printf '200G\n' ;;
  /dev/qvos-test-disk0) printf '1T\n' ;;
  *) exit 32 ;;
  esac
  ;;
VENDOR)
  [[ $device == "/dev/qvos-test-disk0" ]] || exit 32
  printf 'QV\n'
  ;;
MODEL)
  [[ $device == "/dev/qvos-test-disk0" ]] || exit 32
  printf 'QV Secure Disk\n'
  ;;
FSTYPE)
  case $device in
  /dev/qvos-test-a | /dev/qvos-test-b)
    if [[ ${QVOS_TEST_LUKS_DRIFT:-0} == "1" ]]; then
      printf 'ext4\n'
    else
      printf 'crypto_LUKS\n'
    fi
    ;;
  *) printf 'ext4\n' ;;
  esac
  ;;
*)
  printf 'unexpected lsblk request: flags=%s field=%s device=%s\n' \
    "$flags" "$field" "$device" >&2
  exit 2
  ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
[[ $1 == "choose" && $2 == "--header" && $3 == "Select drive" ]] || exit 2
mapfile -t choices
[[ ${QVOS_TEST_GUM_CANCEL:-0} != "1" ]] || exit 1
if [[ -n ${QVOS_TEST_GUM_SELECTION:-} ]]; then
  printf '%s\n' "$QVOS_TEST_GUM_SELECTION"
else
  printf '%s\n' "${choices[0]}"
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/cryptsetup" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >>"$QVOS_TEST_CRYPTSETUP_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} != "--" ]] || shift
exec "$@"
SCRIPT

storage_env=(
  "QVOS_PATH=$root"
  QVOS_STORAGE_TESTING=1
  "QVOS_STORAGE_TEST_BIN=$test_bin"
  "QVOS_TEST_CRYPTSETUP_LOG=$cryptsetup_log"
)

expected_a='/dev/qvos-test-a (100G) - QV Secure Disk [ext4(/), unknown]'
expected_b='/dev/qvos-test-b (200G) - QV Secure Disk [ext4(/), unknown]'
actual=$(env "${storage_env[@]}" "$root/qvcore/storage/info" /dev/qvos-test-a)
[[ $actual == "$expected_a" ]] || fail "bounded drive information"
for invalid in '/dev/../etc/passwd' '/tmp/not-a-drive'; do
  if env "${storage_env[@]}" \
    "$root/qvcore/storage/info" "$invalid" >/dev/null 2>&1; then
    fail "invalid drive path: $invalid"
  fi
done
control_drive=$'/dev/qvos-test-a\e'
if env "${storage_env[@]}" \
  "$root/qvcore/storage/info" "$control_drive" >/dev/null 2>&1; then
  fail "control-character drive path"
fi
printf 'ok - drive details are canonical, bounded, and terminal-safe\n'

selected=$(env "${storage_env[@]}" \
  QVOS_TEST_GUM_SELECTION="$expected_b" \
  "$root/qvcore/storage/select" "/dev/qvos-test-a
/dev/qvos-test-b")
[[ $selected == "/dev/qvos-test-b" ]] || fail "validated drive selection"
set +e
env "${storage_env[@]}" QVOS_TEST_GUM_CANCEL=1 \
  "$root/qvcore/storage/select" /dev/qvos-test-a >/dev/null 2>&1
cancel_status=$?
set -e
((cancel_status == 130)) || fail "drive selection cancellation status"
printf 'ok - drive selection preserves compatibility input and cancellation\n'

: >"$cryptsetup_log"
env "${storage_env[@]}" QVOS_TEST_GUM_SELECTION="$expected_b" \
  "$root/qvcore/storage/password" >/dev/null
expected_cryptsetup=$'luksChangeKey\n--verify-passphrase\n/dev/qvos-test-b'
[[ $(<"$cryptsetup_log") == "$expected_cryptsetup" ]] ||
  fail "exact interactive Cryptsetup delegation"
printf 'ok - LUKS key changes use verified interactive input and current defaults\n'

: >"$cryptsetup_log"
if env "${storage_env[@]}" QVOS_TEST_NO_LUKS=1 \
  "$root/qvcore/storage/password" >/dev/null 2>&1; then
  fail "missing encrypted drives"
fi
[[ ! -s $cryptsetup_log ]] || fail "missing-drive mutation"
if env "${storage_env[@]}" \
  QVOS_TEST_GUM_SELECTION="$expected_b" \
  QVOS_TEST_LUKS_DRIFT=1 \
  "$root/qvcore/storage/password" >/dev/null 2>&1; then
  fail "changed LUKS selection"
fi
[[ ! -s $cryptsetup_log ]] || fail "changed-device mutation"
printf 'ok - absent and changed LUKS devices fail before privileged mutation\n'

compat_info=$(env "${storage_env[@]}" \
  "$root/bin/omarchy-drive-info" /dev/qvos-test-a)
[[ $compat_info == "$expected_a" ]] || fail "drive information compatibility"
"$root/bin/qv" drive password --help | grep -Fq 'qv-drive-password' ||
  fail "native drive password CLI"
QVOS_PATH="$root" "$root/qvcore/storage/check"
printf 'ok - native storage commands and compatibility routes share one owner\n'

mv "$test_bin/lsblk" "$test_bin/lsblk-real"
ln -s "$test_bin/lsblk-real" "$test_bin/lsblk"
if env "${storage_env[@]}" \
  "$root/qvcore/storage/info" /dev/qvos-test-a >/dev/null 2>&1; then
  fail "linked test tool"
fi
printf 'ok - storage fixture overrides reject linked tools\n'
