#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
owner="$root/qvcore/network/regdom"
test_root=$(mktemp -d)
test_bin="$test_root/bin"
iw_log="$test_root/iw.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/iw" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_IW_LOG"
[[ ${QVOS_TEST_IW_FAIL:-0} != "1" ]]
SCRIPT

prepare_root() {
  local system_root=$1

  install -d \
    "$system_root/etc/conf.d" \
    "$system_root/usr/share/zoneinfo"
  install -m 0644 /dev/stdin \
    "$system_root/etc/conf.d/wireless-regdom" <<'REGDOM'
# Wireless regulatory domain configuration
#WIRELESS_REGDOM="EG"
#WIRELESS_REGDOM="US"
REGDOM
  install -m 0644 /dev/stdin \
    "$system_root/usr/share/zoneinfo/zone.tab" <<'ZONES'
EG	+3003+03115	Africa/Cairo
US	+404251-0740023	America/New_York
ZONES
}

run_owner() {
  local system_root=$1
  shift

  QVOS_NETWORK_TESTING=1 \
  QVOS_NETWORK_SYSTEM_ROOT="$system_root" \
  QVOS_NETWORK_IW="$test_bin/iw" \
  QVOS_TEST_IW_LOG="$iw_log" \
  QVOS_NETWORK_TIMEZONE=Africa/Cairo \
    "$owner" "$@"
}

fresh_root="$test_root/fresh"
prepare_root "$fresh_root"
: >"$iw_log"
run_owner "$fresh_root"
fresh_config="$fresh_root/etc/conf.d/wireless-regdom"
[[ $(grep -c '^WIRELESS_REGDOM=' "$fresh_config") == 1 ]] ||
  fail "fresh wireless region is not singular"
grep -Fqx 'WIRELESS_REGDOM="EG"' "$fresh_config" ||
  fail "fresh wireless region selection"
[[ $(<"$iw_log") == "reg set EG" ]] ||
  fail "fresh wireless region activation"
fresh_state=$(stat -c '%i|%Y' "$fresh_config")
run_owner "$fresh_root"
[[ $(stat -c '%i|%Y' "$fresh_config") == "$fresh_state" ]] ||
  fail "idempotent wireless region publication"
[[ $(wc -l <"$iw_log") == 1 ]] ||
  fail "existing wireless region was reactivated"

existing_root="$test_root/existing"
prepare_root "$existing_root"
sed -i 's/^#WIRELESS_REGDOM="US"$/WIRELESS_REGDOM="US"/' \
  "$existing_root/etc/conf.d/wireless-regdom"
existing_before=$(sha256sum "$existing_root/etc/conf.d/wireless-regdom")
: >"$iw_log"
run_owner "$existing_root"
[[ $(sha256sum "$existing_root/etc/conf.d/wireless-regdom") == \
  "$existing_before" && ! -s $iw_log ]] ||
  fail "existing valid wireless region was not preserved"

for form in malformed duplicate; do
  invalid_root="$test_root/$form"
  prepare_root "$invalid_root"
  case $form in
  malformed)
    printf 'WIRELESS_REGDOM=EG\n' \
      >>"$invalid_root/etc/conf.d/wireless-regdom"
    ;;
  duplicate)
    printf 'WIRELESS_REGDOM="EG"\nWIRELESS_REGDOM="US"\n' \
      >>"$invalid_root/etc/conf.d/wireless-regdom"
    ;;
  esac
  invalid_before=$(sha256sum "$invalid_root/etc/conf.d/wireless-regdom")
  if run_owner "$invalid_root" >/dev/null 2>&1; then
    fail "$form wireless region was accepted"
  fi
  [[ $(sha256sum "$invalid_root/etc/conf.d/wireless-regdom") == \
    "$invalid_before" ]] || fail "$form wireless region changed state"
done

linked_root="$test_root/linked"
external="$test_root/external-regdom"
prepare_root "$linked_root"
printf 'external\n' >"$external"
rm -- "$linked_root/etc/conf.d/wireless-regdom"
ln -s "$external" "$linked_root/etc/conf.d/wireless-regdom"
if run_owner "$linked_root" >/dev/null 2>&1; then
  fail "linked wireless region configuration was accepted"
fi
[[ $(<"$external") == "external" ]] ||
  fail "linked wireless region configuration was followed"

rollback_root="$test_root/rollback"
prepare_root "$rollback_root"
rollback_before=$(sha256sum "$rollback_root/etc/conf.d/wireless-regdom")
if QVOS_TEST_IW_FAIL=1 run_owner "$rollback_root" >/dev/null 2>&1; then
  fail "wireless region activation failure was hidden"
fi
[[ $(sha256sum "$rollback_root/etc/conf.d/wireless-regdom") == \
  "$rollback_before" ]] || fail "wireless region activation rollback"

chroot_root="$test_root/chroot"
prepare_root "$chroot_root"
: >"$iw_log"
QVOS_CHROOT_INSTALL=1 run_owner "$chroot_root"
grep -Fqx 'WIRELESS_REGDOM="EG"' \
  "$chroot_root/etc/conf.d/wireless-regdom" ||
  fail "target-chroot wireless region publication"
[[ ! -s $iw_log ]] || fail "target-chroot wireless region changed the builder"

unsafe_root="$test_root/unsafe"
prepare_root "$unsafe_root"
chmod 0777 "$unsafe_root"
if run_owner "$unsafe_root" >/dev/null 2>&1; then
  fail "unsafe wireless-region system root was accepted"
fi
if QVOS_CHROOT_INSTALL=invalid run_owner "$test_root/invalid" \
  >/dev/null 2>&1; then
  fail "invalid wireless-region chroot signal was accepted"
fi

"$root/qvcore/network/check" >/dev/null
"$root/qvcore/install/check" >/dev/null
printf 'ok - wireless region ownership is atomic, singular, and timezone-safe\n'
